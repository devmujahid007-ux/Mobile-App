import 'package:flutter/material.dart';

import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_footer.dart';
import '../widgets/neuroscan_shell.dart';

/// Layout aligned with the web Contact page (heading + details + form card).
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;
  String? _status;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _message.text.trim().isEmpty) {
      setState(() => _status = 'Please fill required fields.');
      return;
    }
    setState(() {
      _sending = true;
      _status = null;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _status = 'Thanks! Your message has been sent.';
      _name.clear();
      _email.clear();
      _subject.clear();
      _message.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'Contact Us',
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact Us',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NeuroScanColors.slate800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Have a question or feedback? Send us a message and we’ll get back to you.',
                    style: TextStyle(color: NeuroScanColors.slate600, fontSize: 15),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 720;
                  final details = _detailsCard();
                  final form = _formCard();
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: details),
                        const SizedBox(width: 20),
                        Expanded(flex: 7, child: form),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      details,
                      const SizedBox(height: 16),
                      form,
                    ],
                  );
                },
              ),
            ),
            const NeuroScanFooter(),
          ],
        ),
      ),
    );
  }

  Widget _detailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NeuroScan AI',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: NeuroScanColors.slate800,
            ),
          ),
          const SizedBox(height: 12),
          _detailRow(Icons.location_on_outlined, 'Research Lab, Lahore, Pakistan'),
          const SizedBox(height: 8),
          _detailRow(Icons.email_outlined, 'support@neuroscan.ai'),
          const SizedBox(height: 8),
          _detailRow(Icons.phone_outlined, '+92 3334773180'),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: NeuroScanColors.slate500),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: NeuroScanColors.slate600, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Send a message',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: NeuroScanColors.slate800,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message *',
              alignLabelWithHint: true,
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: TextStyle(
                color: _status!.startsWith('Thanks')
                    ? Colors.green.shade700
                    : NeuroScanColors.red600,
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send message'),
            ),
          ),
        ],
      ),
    );
  }
}
