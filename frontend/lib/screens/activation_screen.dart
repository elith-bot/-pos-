import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'auth_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});
  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final token = TextEditingController();
  Map<String, dynamic>? status;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await ApiService.businessRequest('/api/license');
      if (!mounted) return;
      if (value['active'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      } else {
        setState(() => status = value);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submitActivation() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ApiService.businessRequest(
        '/api/license/activate',
        method: 'POST',
        body: {'token': token.text.trim()},
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              const Icon(Icons.verified_user_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'تفعيل نسخة الكاشير',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const Text(
                'انسخ كود الطلب وأرسله إلى مجهّز النظام، ثم أدخل رمز التفعيل الخاص بهذا الجهاز. لا يحتاج الكاشير إلى الإنترنت للتفعيل أو التشغيل.',
              ),
              const SizedBox(height: 16),
              Text('${status?['message'] ?? ''}'),
              if (status?['request_code'] != null) ...[
                SelectableText(
                  '${status!['request_code']}',
                  textDirection: TextDirection.ltr,
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: '${status!['request_code']}'),
                          );
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ كود الطلب')),
                            );
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ كود طلب التفعيل'),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: token,
                enabled: !busy,
                minLines: 4,
                maxLines: 8,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رمز التفعيل',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy || status?['request_code'] == null
                    ? null
                    : submitActivation,
                child: const Text('تفعيل النسخة'),
              ),
              TextButton(
                onPressed: busy ? null : load,
                child: const Text('إعادة الفحص'),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
