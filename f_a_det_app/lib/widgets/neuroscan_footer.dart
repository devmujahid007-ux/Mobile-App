import 'package:flutter/material.dart';

import '../theme/neuroscan_theme.dart';

/// Matches the web footer: gradient blue-900 → slate-900, quick links, contact strip.
class NeuroScanFooter extends StatelessWidget {
  const NeuroScanFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NeuroScanColors.blue900,
            NeuroScanColors.slate900,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              final children = [
                _brandBlock(),
                _quickLinks(context),
                _resourcesLinks(context),
                _contactBlock(),
              ];
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: children[0]),
                    Expanded(child: children[1]),
                    Expanded(child: children[2]),
                    Expanded(child: children[3]),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  children[0],
                  const SizedBox(height: 24),
                  children[1],
                  const SizedBox(height: 24),
                  children[2],
                  const SizedBox(height: 24),
                  children[3],
                ],
              );
            },
          ),
          const Divider(color: Color(0xFF334155), height: 40),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 520;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment:
                    narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Text(
                    '© $year NeuroScan AI — All Rights Reserved.',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                  ),
                  if (!narrow) const SizedBox(width: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: const [
                      _SocialLabel('Twitter'),
                      _SocialLabel('GitHub'),
                      _SocialLabel('LinkedIn'),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _brandBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NeuroScan AI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13, height: 1.5),
            children: const [
              TextSpan(text: 'Revolutionizing early detection of\n'),
              TextSpan(
                text: 'Brain Tumor & Alzheimer\'s Disease',
                style: TextStyle(color: NeuroScanColors.blue400),
              ),
              TextSpan(
                text: ' using advanced MRI analytics.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickLinks(BuildContext context) {
    return _linkColumn(
      'Quick Links',
      [
        _FooterLink('Home', () => Navigator.pushNamed(context, '/home')),
        _FooterLink('About', () => Navigator.pushNamed(context, '/about')),
        _FooterLink('FAQ', () => Navigator.pushNamed(context, '/about')),
      ],
    );
  }

  Widget _resourcesLinks(BuildContext context) {
    return _linkColumn(
      'Resources',
      [
        _FooterLink('Documentation', () => Navigator.pushNamed(context, '/about')),
        _FooterLink('Research Papers', () => Navigator.pushNamed(context, '/about')),
        _FooterLink('Support', () => Navigator.pushNamed(context, '/contact')),
        _FooterLink('Contact', () => Navigator.pushNamed(context, '/contact')),
      ],
    );
  }

  Widget _linkColumn(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...items.map((w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w)),
      ],
    );
  }

  Widget _contactBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Us',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Email: neuroscan.ai @gmail.com',
          style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Phone: +92 3334773180',
          style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Location: Research Lab, Lahore, Pakistan',
          style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
        ),
      ],
    );
  }

}

class _SocialLabel extends StatelessWidget {
  final String label;
  const _SocialLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(color: NeuroScanColors.blue400, fontSize: 13),
      ),
    );
  }
}
