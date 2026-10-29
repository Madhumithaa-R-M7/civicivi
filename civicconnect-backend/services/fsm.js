/**
 * CivicConnect Finite-State Machine (FSM) Engine (Algorithm 13)
 * Enforces complaint lifecycle transitions, role authorization, and atomic audit logging.
 */

const db = require('../db');

// Valid complaint lifecycle states
const COMPLAINT_STATES = {
  SUBMITTED: 'SUBMITTED',
  VERIFIED: 'VERIFIED',
  ASSIGNED: 'ASSIGNED',
  IN_PROGRESS: 'IN_PROGRESS',
  RESOLVED: 'RESOLVED',
  CLOSED: 'CLOSED',
  REJECTED: 'REJECTED',
  REOPENED: 'REOPENED',
};

// Legacy alias mapping for backward compatibility
const STATE_ALIASES = {
  'Pending': 'SUBMITTED',
  'In Progress': 'IN_PROGRESS',
  'Resolved': 'RESOLVED',
  'Rejected': 'REJECTED',
  'Closed': 'CLOSED',
};

function normalizeState(state) {
  if (!state) return state;
  const trimmed = state.trim();
  if (STATE_ALIASES[trimmed]) return STATE_ALIASES[trimmed];
  const upper = trimmed.toUpperCase().replace(/\s+/g, '_');
  return COMPLAINT_STATES[upper] || upper;
}

// Transition matrix defining permissible target states and required privilege levels
const FSM_TRANSITIONS = {
  SUBMITTED: {
    allowed: ['VERIFIED', 'ASSIGNED', 'REJECTED'],
    roles: ['staff', 'admin', 'super_admin'],
  },
  VERIFIED: {
    allowed: ['ASSIGNED', 'IN_PROGRESS', 'REJECTED'],
    roles: ['staff', 'admin', 'super_admin'],
  },
  ASSIGNED: {
    allowed: ['IN_PROGRESS', 'ASSIGNED', 'REJECTED'], // 'ASSIGNED' allows re-assignment
    roles: ['staff', 'admin', 'super_admin'],
  },
  IN_PROGRESS: {
    allowed: ['RESOLVED', 'ASSIGNED', 'REJECTED'],
    roles: ['staff', 'admin', 'super_admin'],
  },
  RESOLVED: {
    allowed: ['CLOSED', 'REOPENED'],
    roles: ['user', 'staff', 'admin', 'super_admin'],
  },
  REOPENED: {
    allowed: ['ASSIGNED', 'IN_PROGRESS', 'REJECTED'],
    roles: ['staff', 'admin', 'super_admin'],
  },
  CLOSED: {
    allowed: ['REOPENED'],
    roles: ['admin', 'super_admin'],
  },
  REJECTED: {
    allowed: ['REOPENED'],
    roles: ['admin', 'super_admin'],
  },
};

/**
 * Execute an atomic FSM status transition with row locking and audit trail.
 *
 * @param {Object} params
 * @param {number} params.complaintId
 * @param {string} params.targetStatus
 * @param {Object} params.actor - Authenticated user { id, role, name }
 * @param {string} [params.reason]
 * @param {string} [params.resolutionNotes]
 * @param {number} [params.assignedTo]
 * @param {number} [params.departmentId]
 * @param {Object} [params.metadata]
 * @returns {Promise<Object>} Updated complaint record
 */
async function transitionComplaintStatus({
  complaintId,
  targetStatus,
  actor,
  reason = '',
  resolutionNotes = '',
  assignedTo = null,
  departmentId = null,
  metadata = {},
}) {
  const normTarget = normalizeState(targetStatus);
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    // Pessimistic lock row for concurrency control (Algorithm 19)
    const complaintRes = await client.query(
      `SELECT * FROM complaints WHERE id = $1 FOR UPDATE`,
      [complaintId]
    );

    if (complaintRes.rows.length === 0) {
      const err = new Error('Complaint not found');
      err.status = 404;
      throw err;
    }

    const complaint = complaintRes.rows[0];
    const currentStatus = normalizeState(complaint.status);
    const actorRole = actor.role || 'user';
    const isOwner = complaint.user_id === actor.id;

    // Check if target status is valid
    if (!COMPLAINT_STATES[normTarget]) {
      const err = new Error(`Invalid target status: '${targetStatus}'. Allowed: ${Object.keys(COMPLAINT_STATES).join(', ')}`);
      err.status = 400;
      throw err;
    }

    // Check self-transition (idempotency check)
    if (currentStatus === normTarget) {
      await client.query('COMMIT');
      return complaint;
    }

    // Retrieve transition rules for current status
    const rule = FSM_TRANSITIONS[currentStatus];
    if (!rule || !rule.allowed.includes(normTarget)) {
      const allowedStr = rule ? rule.allowed.join(', ') : 'None';
      const err = new Error(
        `Invalid status transition from '${currentStatus}' to '${normTarget}'. Permissible transitions: [${allowedStr}]`
      );
      err.status = 400;
      throw err;
    }

    // Role-based authorization guard
    if (actorRole === 'user') {
      // Citizen users can only close or dispute/reopen their OWN resolved complaints
      if (!isOwner || currentStatus !== 'RESOLVED' || !['CLOSED', 'REOPENED'].includes(normTarget)) {
        const err = new Error('Forbidden: Citizens can only confirm closure or dispute/reopen their own resolved complaints');
        err.status = 403;
        throw err;
      }
    } else if (!rule.roles.includes(actorRole)) {
      const err = new Error(`Forbidden: Role '${actorRole}' is not authorized to perform transition '${currentStatus}' -> '${normTarget}'`);
      err.status = 403;
      throw err;
    }

    // Validation for specific target statuses
    if (normTarget === 'REJECTED' && (!reason || reason.trim().length === 0)) {
      const err = new Error('Rejection requires a non-empty reason explaining why the complaint was rejected');
      err.status = 400;
      throw err;
    }

    if (normTarget === 'RESOLVED' && (!resolutionNotes || resolutionNotes.trim().length === 0)) {
      const err = new Error('Marking a complaint as RESOLVED requires resolution notes detailing actions taken');
      err.status = 400;
      throw err;
    }

    // Update complaint record
    const updateRes = await client.query(
      `UPDATE complaints
       SET status = $1,
           resolution_notes = COALESCE($2, resolution_notes),
           assigned_to = COALESCE($3, assigned_to),
           department_id = COALESCE($4, department_id),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $5
       RETURNING *`,
      [normTarget, resolutionNotes || null, assignedTo || null, departmentId || null, complaintId]
    );

    const updatedComplaint = updateRes.rows[0];

    // If assigned to a staff member, update staff workload and log assignment
    if (normTarget === 'ASSIGNED' && assignedTo) {
      await client.query(
        `INSERT INTO complaint_assignments (complaint_id, staff_id, department_id, assigned_by, notes)
         VALUES ($1, $2, $3, $4, $5)`,
        [complaintId, assignedTo, departmentId || updatedComplaint.department_id, actor.id, reason || 'Staff assigned']
      );

      // Increment staff profile current workload
      await client.query(
        `UPDATE staff_profiles 
         SET current_load = current_load + 1, updated_at = CURRENT_TIMESTAMP 
         WHERE user_id = $1`,
        [assignedTo]
      );
    }

    // Update SLA record milestones
    if (normTarget === 'IN_PROGRESS') {
      await client.query(
        `UPDATE sla_records 
         SET responded_at = COALESCE(responded_at, CURRENT_TIMESTAMP) 
         WHERE complaint_id = $1`,
        [complaintId]
      );
    } else if (normTarget === 'RESOLVED') {
      await client.query(
        `UPDATE sla_records 
         SET resolved_at = COALESCE(resolved_at, CURRENT_TIMESTAMP) 
         WHERE complaint_id = $1`,
        [complaintId]
      );

      // Award bonus points to citizen owner
      if (complaint.user_id) {
        await client.query('UPDATE users SET points = points + 25 WHERE id = $1', [complaint.user_id]);
        await client.query(
          `INSERT INTO points_log (user_id, complaint_id, points, reason)
           VALUES ($1, $2, 25, 'Complaint successfully resolved by municipality')`,
          [complaint.user_id, complaintId]
        );
      }
    }

    // Record FSM Status History Audit Trail
    await client.query(
      `INSERT INTO status_history (complaint_id, from_status, to_status, changed_by, reason, metadata)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [complaintId, currentStatus, normTarget, actor.id, reason || resolutionNotes || null, JSON.stringify(metadata)]
    );

    // Record system Audit Log (Algorithm 18)
    await client.query(
      `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, old_values, new_values)
       VALUES ($1, 'COMPLAINT_STATUS_CHANGE', 'complaints', $2, $3, $4)`,
      [
        actor.id,
        complaintId,
        JSON.stringify({ status: currentStatus, assigned_to: complaint.assigned_to }),
        JSON.stringify({ status: normTarget, assigned_to: updatedComplaint.assigned_to }),
      ]
    );

    // Notify citizen owner of status update
    if (complaint.user_id && complaint.user_id !== actor.id) {
      let title = `Complaint #${complaintId} Update`;
      let desc = `Status changed to: ${normTarget}`;

      if (normTarget === 'RESOLVED') {
        title = 'Issue Resolved!';
        desc = `Your reported issue "${complaint.category}" has been marked as Resolved. +25 Civic Points!`;
      } else if (normTarget === 'IN_PROGRESS') {
        title = 'Work in Progress';
        desc = `Municipal field teams have begun work on your issue "${complaint.category}".`;
      } else if (normTarget === 'REJECTED') {
        title = 'Report Notice';
        desc = `Your issue "${complaint.category}" could not be processed: ${reason}`;
      }

      await client.query(
        `INSERT INTO notifications (user_id, complaint_id, title, description, type)
         VALUES ($1, $2, $3, $4, 'status_update')`,
        [complaint.user_id, complaintId, title, desc]
      );
    }

    await client.query('COMMIT');
    return updatedComplaint;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Fetch chronological status history timeline for a complaint
 */
async function getComplaintHistory(complaintId) {
  const result = await db.query(
    `SELECT sh.id, sh.complaint_id, sh.from_status, sh.to_status, 
            sh.reason, sh.metadata, sh.created_at,
            u.name as changed_by_name, u.role as changed_by_role
     FROM status_history sh
     LEFT JOIN users u ON sh.changed_by = u.id
     WHERE sh.complaint_id = $1
     ORDER BY sh.created_at ASC`,
    [complaintId]
  );
  return result.rows;
}

module.exports = {
  COMPLAINT_STATES,
  FSM_TRANSITIONS,
  normalizeState,
  transitionComplaintStatus,
  getComplaintHistory,
};
