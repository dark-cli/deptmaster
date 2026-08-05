import 'package:flutter/material.dart';

class ManagementSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ManagementTile> tiles;

  const ManagementSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => tiles[index],
          ),
        ],
      ),
    );
  }
}

class ManagementTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final VoidCallback onTap;

  const ManagementTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leadingIcon != null ? Icon(leadingIcon) : null,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
