import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../core/utils.dart';

class ThankYouMessageService {
  // Official Markaz Knowledge City Thank You Message Template
  static const String officialTemplate = '''Thank you for visiting Markaz Knowledge City.

We truly appreciate your time and interest in our vision and initiatives. It was a pleasure hosting you and we look forward to your continued support and cooperation.

If there were any shortcomings or inconveniences during your visit, we kindly seek your understanding and forgiveness.

For any future communication or assistance, please feel free to contact us at +91 62359 98805.

Warm regards,

Guest Relations/ Outreach Department
Markaz Knowledge City''';

  // Format phone number to clean international digits format (e.g. +91 9876543210 -> 919876543210)
  static String cleanPhoneNumber(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '91$digits'; // Add default India country code if 10 digits provided
    }
    return digits;
  }

  // Show Interactive Thank You Message Dialog with WhatsApp & SMS options
  static Future<void> showThankYouDialog(
    BuildContext context, {
    required String guestName,
    required String phoneNumber,
  }) async {
    final formattedPhone = cleanPhoneNumber(phoneNumber);
    final displayPhone = phoneNumber.trim().isNotEmpty ? phoneNumber.trim() : 'No Phone Number Recorded';
    final nameStr = guestName.trim().isNotEmpty ? guestName.trim() : 'Guest';
    final String fullMessage = 'Dear $nameStr,\n\n$officialTemplate';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFF059669), size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Send Thank You Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Automated Guest Appreciation', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Detected Guest Details Header Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_pin_rounded, color: Color(0xFF059669), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nameStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('Detected Phone: $displayPhone', style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Official Message Content:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: fullMessage));
                        AppUtils.showSnackBar(context, 'Message copied to clipboard!');
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text('Copy Text', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Scrollable Message Body Box
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      fullMessage,
                      style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF1E293B)),
                    ),
                  ),
                ),

                const SizedBox(height: 18),
                const Text('Select Delivery Channel:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 10),

                // Option 1: WhatsApp Button (Vibrant Green)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openWhatsApp(context, phone: formattedPhone, message: fullMessage);
                  },
                  icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
                  label: const Text('Send via WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                ),

                const SizedBox(height: 10),

                // Option 2: SMS Button (Sky Blue)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openSms(context, phone: formattedPhone, message: fullMessage);
                  },
                  icon: const Icon(Icons.sms_rounded, color: Colors.white, size: 20),
                  label: const Text('Send via SMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip / Close', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // Open WhatsApp Web/App with pre-filled message
  static Future<void> openWhatsApp(
    BuildContext context, {
    required String phone,
    required String message,
  }) async {
    final encodedMsg = Uri.encodeComponent(message);
    final waUrl = Uri.parse('https://wa.me/$phone?text=$encodedMsg');
    final apiUrl = Uri.parse('https://api.whatsapp.com/send?phone=$phone&text=$encodedMsg');

    try {
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(apiUrl)) {
        await launchUrl(apiUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(waUrl, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(waUrl, mode: LaunchMode.platformDefault);
      } catch (e) {
        if (context.mounted) {
          AppUtils.showSnackBar(context, 'Could not launch WhatsApp: $e', isError: true);
        }
      }
    }
  }

  // Open SMS application with pre-filled message
  static Future<void> openSms(
    BuildContext context, {
    required String phone,
    required String message,
  }) async {
    final encodedMsg = Uri.encodeComponent(message);
    final smsUri = Uri.parse('sms:$phone?body=$encodedMsg');

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        final altSmsUri = Uri.parse('sms:$phone&body=$encodedMsg');
        await launchUrl(altSmsUri);
      }
    } catch (e) {
      if (context.mounted) {
        AppUtils.showSnackBar(context, 'Could not launch SMS: $e', isError: true);
      }
    }
  }
}
