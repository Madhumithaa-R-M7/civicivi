/**
 * Real SMS Gateway Service for CivicConnect
 *
 * Supports:
 * - TextBee: TEXTBEE_API_KEY (textbee.dev Android SMS gateway)
 * - Fast2SMS: FAST2SMS_API_KEY (Recommended for Indian numbers)
 * - Twilio: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER
 * - Mock mode: only enabled when SMS_PROVIDER=mock or SMS_PROVIDER=dev in non-production.
 *
 * If credentials are missing, this service throws an explicit configuration error
 * rather than falsely reporting success.
 */

const https = require('https');

/**
 * Send SMS OTP using configured SMS provider
 * @param {string} phoneNumber - Destination phone number (e.g. +919876543210)
 * @param {string} otp - 6-digit verification code
 * @returns {Promise<{sent: boolean, provider: string, messageId?: string, accepted?: boolean, devOtp?: string}>}
 */
async function sendSms(phoneNumber, otp) {
  const message = `Your CivicConnect verification code is: ${otp}. Valid for 5 minutes. Do not share this code with anyone.`;
  const provider = (process.env.SMS_PROVIDER || '').trim().toLowerCase();

  console.log(`\n--------------------------------------------------`);
  console.log(`📲 [SMS GATEWAY] Initiating OTP dispatch...`);
  console.log(`Target Phone     : ${phoneNumber}`);
  console.log(`Selected Provider: ${provider || '(auto-detect from credentials)'}`);

  // -------------------------------------------------------------
  // 1. TEXTBEE PROVIDER (textbee.dev Android Gateway)
  // -------------------------------------------------------------
  if (provider === 'textbee' || (!provider && process.env.TEXTBEE_API_KEY)) {
    const apiKey = (process.env.TEXTBEE_API_KEY || '').trim();

    if (!apiKey) {
      const err = new Error(
        'TextBee is selected as the SMS provider, but TEXTBEE_API_KEY is not configured in civicconnect-backend/.env. Please set TEXTBEE_API_KEY.'
      );
      console.error(`[SMS-TEXTBEE] ❌ Configuration Error: ${err.message}`);
      throw err;
    }

    console.log(`[SMS-TEXTBEE] Dispatching request to TextBee API for ${phoneNumber}...`);

    const postPayload = {
      recipients: [phoneNumber],
      message: message,
    };
    if (process.env.TEXTBEE_DEVICE_ID && process.env.TEXTBEE_DEVICE_ID.trim().length > 0) {
      postPayload.deviceId = process.env.TEXTBEE_DEVICE_ID.trim();
    }

    const postData = JSON.stringify(postPayload);

    const textbeeResponse = await new Promise((resolve, reject) => {
      const req = https.request(
        {
          hostname: 'api.textbee.dev',
          port: 443,
          path: '/api/v1/gateway/send-sms',
          method: 'POST',
          headers: {
            'x-api-key': apiKey,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData),
          },
        },
        (res) => {
          let data = '';
          res.on('data', (chunk) => (data += chunk));
          res.on('end', () => {
            try {
              const parsed = JSON.parse(data);
              resolve({ statusCode: res.statusCode, body: parsed, raw: data });
            } catch (_) {
              resolve({ statusCode: res.statusCode, raw: data });
            }
          });
        }
      );

      req.on('error', (err) => {
        reject(new Error(`TextBee network connection failed: ${err.message}`));
      });

      req.write(postData);
      req.end();
    });

    const isAccepted =
      textbeeResponse.statusCode === 200 &&
      textbeeResponse.body &&
      (textbeeResponse.body.data?.success === true || textbeeResponse.body.data?.smsBatchId);

    if (isAccepted) {
      const batchId = textbeeResponse.body.data?.smsBatchId || 'N/A';
      console.log(`[SMS-TEXTBEE] ✅ TextBee accepted message into dispatch queue! Batch ID: ${batchId}`);
      console.log(`--------------------------------------------------\n`);
      return {
        sent: true,
        provider: 'textbee',
        messageId: batchId,
        accepted: true,
      };
    } else {
      const errDetail =
        textbeeResponse.body?.error ||
        textbeeResponse.body?.message ||
        textbeeResponse.raw ||
        'TextBee dispatch rejected';
      console.error(`[SMS-TEXTBEE] ❌ TextBee Error (HTTP ${textbeeResponse.statusCode}):`, errDetail);
      console.log(`--------------------------------------------------\n`);
      if (typeof errDetail === 'string' && errDetail.toLowerCase().includes('no enabled device')) {
        throw new Error(
          'TextBee Error: No enabled Android device found on your TextBee account. Please open the TextBee app on your phone, sign in, and pair your phone.'
        );
      }
      throw new Error(`TextBee gateway error: ${errDetail}`);
    }
  }

  // -------------------------------------------------------------
  // 2. FAST2SMS PROVIDER (Primary / Recommended for India)
  // -------------------------------------------------------------
  if (provider === 'fast2sms' || (!provider && process.env.FAST2SMS_API_KEY)) {
    const apiKey = (process.env.FAST2SMS_API_KEY || '').trim();

    if (!apiKey) {
      const err = new Error(
        'Fast2SMS is selected as the SMS provider, but FAST2SMS_API_KEY is not configured in civicconnect-backend/.env. Please set FAST2SMS_API_KEY.'
      );
      console.error(`[SMS-FAST2SMS] ❌ Configuration Error: ${err.message}`);
      throw err;
    }

    const cleanPhone = phoneNumber.replace(/^\+91/, '').replace(/\D/g, '').slice(-10);
    if (cleanPhone.length !== 10) {
      throw new Error(`Fast2SMS requires a 10-digit Indian mobile number. Provided: ${phoneNumber}`);
    }

    console.log(`[SMS-FAST2SMS] Dispatching request to Fast2SMS API for ${cleanPhone}...`);

    const postData = JSON.stringify({
      route: 'otp',
      variables_values: otp,
      numbers: cleanPhone,
    });

    const fast2smsResponse = await new Promise((resolve, reject) => {
      const req = https.request(
        {
          hostname: 'www.fast2sms.com',
          port: 443,
          path: '/dev/bulkV2',
          method: 'POST',
          headers: {
            authorization: apiKey,
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'Content-Length': Buffer.byteLength(postData),
          },
        },
        (res) => {
          let data = '';
          res.on('data', (chunk) => (data += chunk));
          res.on('end', () => {
            try {
              const parsed = JSON.parse(data);
              resolve({ statusCode: res.statusCode, body: parsed, raw: data });
            } catch (_) {
              resolve({ statusCode: res.statusCode, raw: data });
            }
          });
        }
      );

      req.on('error', (err) => {
        reject(new Error(`Fast2SMS network connection failed: ${err.message}`));
      });

      req.write(postData);
      req.end();
    });

    // Check Fast2SMS gateway acceptance
    const isAccepted =
      fast2smsResponse.statusCode === 200 &&
      fast2smsResponse.body &&
      fast2smsResponse.body.return === true;

    if (isAccepted) {
      const requestId = fast2smsResponse.body?.request_id || 'N/A';
      console.log(`[SMS-FAST2SMS] ✅ Fast2SMS gateway accepted request! Request ID: ${requestId}`);
      console.log(`--------------------------------------------------\n`);
      return {
        sent: true,
        provider: 'fast2sms',
        messageId: requestId,
        accepted: true,
      };
    } else {
      const fast2smsMsg =
        fast2smsResponse.body?.message || fast2smsResponse.raw || 'Fast2SMS gateway rejected the dispatch request';
      console.error(`[SMS-FAST2SMS] ❌ Fast2SMS Gateway Rejected:`, fast2smsMsg);
      console.log(`--------------------------------------------------\n`);
      throw new Error(
        `Fast2SMS gateway error: ${Array.isArray(fast2smsMsg) ? fast2smsMsg.join(', ') : fast2smsMsg}`
      );
    }
  }

  // -------------------------------------------------------------
  // 2. TWILIO PROVIDER (Alternative Provider)
  // -------------------------------------------------------------
  if (provider === 'twilio' || (!provider && process.env.TWILIO_ACCOUNT_SID)) {
    const accountSid = (process.env.TWILIO_ACCOUNT_SID || '').trim();
    const authToken = (process.env.TWILIO_AUTH_TOKEN || '').trim();
    const fromNumber = (process.env.TWILIO_PHONE_NUMBER || '').trim();

    if (!accountSid || !authToken || !fromNumber) {
      const err = new Error(
        'Twilio is selected as the SMS provider, but TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, or TWILIO_PHONE_NUMBER is missing in civicconnect-backend/.env.'
      );
      console.error(`[SMS-TWILIO] ❌ Configuration Error: ${err.message}`);
      throw err;
    }

    console.log(`[SMS-TWILIO] Sending request to Twilio API for ${phoneNumber}...`);

    const auth = Buffer.from(`${accountSid}:${authToken}`).toString('base64');
    const postData = new URLSearchParams({
      To: phoneNumber,
      From: fromNumber,
      Body: message,
    }).toString();

    const twilioResponse = await new Promise((resolve, reject) => {
      const req = https.request(
        {
          hostname: 'api.twilio.com',
          port: 443,
          path: `/2010-04-01/Accounts/${accountSid}/Messages.json`,
          method: 'POST',
          headers: {
            Authorization: `Basic ${auth}`,
            'Content-Type': 'application/x-www-form-urlencoded',
            'Content-Length': Buffer.byteLength(postData),
          },
        },
        (res) => {
          let data = '';
          res.on('data', (chunk) => (data += chunk));
          res.on('end', () => {
            try {
              const parsed = JSON.parse(data);
              resolve({ statusCode: res.statusCode, body: parsed, raw: data });
            } catch (_) {
              resolve({ statusCode: res.statusCode, raw: data });
            }
          });
        }
      );

      req.on('error', (err) => {
        reject(new Error(`Twilio network request failed: ${err.message}`));
      });

      req.write(postData);
      req.end();
    });

    if (twilioResponse.statusCode >= 200 && twilioResponse.statusCode < 300) {
      console.log(`[SMS-TWILIO] ✅ Twilio gateway accepted request! SID: ${twilioResponse.body?.sid || 'N/A'}, Status: ${twilioResponse.body?.status || 'sent'}`);
      console.log(`--------------------------------------------------\n`);
      return {
        sent: true,
        provider: 'twilio',
        messageId: twilioResponse.body?.sid,
        accepted: true,
      };
    } else {
      const twilioCode = twilioResponse.body?.code;
      const twilioMsg = twilioResponse.body?.message || twilioResponse.raw;
      console.error(`[SMS-TWILIO] ❌ Twilio Error (HTTP ${twilioResponse.statusCode}, Code ${twilioCode}): ${twilioMsg}`);

      if (twilioCode === 21608) {
        console.error(`[SMS-TWILIO] ⚠️ NOTE: Twilio trial accounts can only send SMS to numbers verified in your Twilio Console!`);
      }
      console.log(`--------------------------------------------------\n`);
      throw new Error(`Twilio delivery failed (Code ${twilioCode}): ${twilioMsg}`);
    }
  }

  // -------------------------------------------------------------
  // 3. MOCK / DEV MODE (Explicitly enabled for testing)
  // -------------------------------------------------------------
  if (provider === 'mock' || provider === 'dev') {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('Mock SMS provider cannot be used in a production environment!');
    }

    console.log(`[SMS-MOCK] 🧪 Mock SMS Provider active (for testing only).`);
    console.log(`👉👉👉 TEST OTP CODE: ${otp} 👈👈👈`);
    console.log(`--------------------------------------------------\n`);

    return {
      sent: true,
      provider: 'mock',
      devOtp: otp,
      accepted: true,
    };
  }

  // -------------------------------------------------------------
  // 4. MISSING CONFIGURATION ERROR (Never falsely report success!)
  // -------------------------------------------------------------
  console.error(`[SMS GATEWAY] ❌ No SMS provider credentials configured in .env!`);
  console.log(`--------------------------------------------------\n`);
  throw new Error(
    'SMS provider is not configured. Please add FAST2SMS_API_KEY or TWILIO credentials in civicconnect-backend/.env'
  );
}

module.exports = { sendSms };
