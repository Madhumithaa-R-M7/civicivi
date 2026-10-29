/**
 * Resend Email Service for CivicConnect Password Recovery
 *
 * Requirements:
 * - RESEND_API_KEY: API key from resend.com dashboard (e.g. re_...)
 * - RESEND_FROM_EMAIL: Sender address (e.g. 'CivicConnect <onboarding@resend.dev>' or verified domain)
 */

const { Resend } = require('resend');

/**
 * Send Password Reset OTP email via Resend
 * @param {string} toEmail - Recipient user email
 * @param {string} otp - 6-digit recovery OTP
 * @returns {Promise<{sent: boolean, provider: string, messageId?: string, devOtp?: string}>}
 */
async function sendPasswordResetEmail(toEmail, otp) {
  const apiKey = (process.env.RESEND_API_KEY || '').trim();
  const fromEmail = (process.env.RESEND_FROM_EMAIL || 'CivicConnect <onboarding@resend.dev>').trim();

  console.log(`\n--------------------------------------------------`);
  console.log(`📧 [EMAIL GATEWAY] Initiating Password Reset OTP dispatch...`);
  console.log(`Target Email: ${toEmail}`);

  // 1. Live Resend dispatch if API key is provided
  if (apiKey) {
    try {
      console.log(`[EMAIL-RESEND] Sending OTP via Resend to ${toEmail}...`);
      const resend = new Resend(apiKey);

      const htmlContent = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f8fafc; margin: 0; padding: 0; color: #1e293b; }
            .container { max-width: 520px; margin: 30px auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.06); border: 1px solid #e2e8f0; }
            .header { background: #2962FF; padding: 32px 24px; text-align: center; color: #ffffff; }
            .header h1 { margin: 0; font-size: 24px; font-weight: 700; letter-spacing: -0.5px; }
            .content { padding: 32px 24px; }
            .otp-box { background: #f1f5f9; border-radius: 12px; padding: 20px; text-align: center; margin: 24px 0; border: 2px dashed #cbd5e1; }
            .otp-code { font-size: 36px; font-weight: 800; letter-spacing: 10px; color: #1a237e; font-family: 'Courier New', monospace; }
            .notice { font-size: 14px; color: #64748b; line-height: 1.6; margin-top: 20px; }
            .footer { padding: 20px 24px; text-align: center; font-size: 12px; color: #94a3b8; background: #f8fafc; border-top: 1px solid #e2e8f0; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1>CivicConnect</h1>
              <p style="margin: 6px 0 0; opacity: 0.9; font-size: 14px;">Password Recovery Request</p>
            </div>
            <div class="content">
              <p style="font-size: 16px; margin: 0 0 12px;">Hello,</p>
              <p style="font-size: 15px; color: #475569; line-height: 1.5; margin: 0;">
                We received a request to reset your password for your CivicConnect citizen account. Use the verification code below to proceed:
              </p>
              <div class="otp-box">
                <div class="otp-code">${otp}</div>
                <p style="margin: 8px 0 0; font-size: 13px; color: #64748b;">This code is valid for 10 minutes</p>
              </div>
              <p class="notice">
                <strong>Didn't request this?</strong> You can safely ignore this email. Your password will remain unchanged, and your account is secure.
              </p>
            </div>
            <div class="footer">
              CivicConnect &copy; 2026. Empowering citizens for better neighborhoods.
            </div>
          </div>
        </body>
        </html>
      `;

      const { data, error } = await resend.emails.send({
        from: fromEmail,
        to: toEmail,
        subject: 'CivicConnect — Your Password Reset Code',
        html: htmlContent,
      });

      if (error) {
        console.error(`[EMAIL-RESEND] ❌ Resend Error:`, error);
        throw new Error(`Resend email delivery failed: ${error.message || JSON.stringify(error)}`);
      }

      console.log(`[EMAIL-RESEND] ✅ Password reset email accepted by Resend! ID: ${data?.id}`);
      console.log(`--------------------------------------------------\n`);
      return {
        sent: true,
        provider: 'resend',
        messageId: data?.id,
      };
    } catch (err) {
      console.error(`[EMAIL-RESEND] ❌ Dispatch Error:`, err.message);
      console.log(`--------------------------------------------------\n`);
      throw err;
    }
  }

  // 2. Fallback in development mode if RESEND_API_KEY is not set
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Email delivery failed: RESEND_API_KEY is not configured in production environment!');
  }

  console.log(`[EMAIL-DEV-MODE] ⚠️ RESEND_API_KEY is not set in .env.`);
  console.log(`[EMAIL-DEV-MODE] Set RESEND_API_KEY=re_... in .env to deliver real recovery emails.`);
  console.log(`[EMAIL-DEV-MODE] For testing, use the OTP code below:`);
  console.log(`👉👉👉 PASSWORD RESET DEV OTP: ${otp} 👈👈👈`);
  console.log(`--------------------------------------------------\n`);

  return {
    sent: true,
    provider: 'dev-console',
    devOtp: otp,
  };
}

module.exports = { sendPasswordResetEmail };
