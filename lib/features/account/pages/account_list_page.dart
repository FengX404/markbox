import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/account_config_state.dart';
import '../../../shared/models/imap_config.dart';
import '../../../shared/providers/account_config_provider.dart';
import '../../../shared/themes/app_colors.dart';
import '../../../shared/themes/app_text_styles.dart';
import '../../../shared/themes/app_spacing.dart';
import '../../../shared/routes/animated_page_route.dart';
import 'imap_config_page.dart';
import 'provider_selection_page.dart';

/// 已配置邮箱列表页面
///
/// 显示所有已配置的邮箱账户，支持编辑和删除操作
class AccountListPage extends ConsumerStatefulWidget {
  const AccountListPage({super.key});

  @override
  ConsumerState<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends ConsumerState<AccountListPage> {
  @override
  void initState() {
    super.initState();
    // 加载配置列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(accountConfigProvider.notifier).loadConfigs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountConfig = ref.watch(accountConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的邮箱'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _buildBody(accountConfig),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddAccount(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(AccountConfigState accountConfig) {
    // 加载中
    if (accountConfig.isLoading && !accountConfig.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // 空列表
    if (accountConfig.isInitialized && accountConfig.configs.isEmpty) {
      return _buildEmptyState();
    }

    // 正常列表
    return _buildAccountList(accountConfig.configs);
  }

  /// 刷新邮箱配置列表
  Future<void> _onRefresh() async {
    await ref.read(accountConfigProvider.notifier).loadConfigs();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppEdgeInsets.page,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              '暂无邮箱配置',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮添加邮箱账户',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountList(List<ImapConfig> configs) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppEdgeInsets.vertical8,
        itemCount: configs.length,
        itemBuilder: (context, index) {
          final config = configs[index];
          return _AccountListItem(
            config: config,
            onEdit: () => _navigateToEditAccount(context, config),
            onDelete: () => _confirmDelete(context, config),
          );
        },
      ),
    );
  }

  void _navigateToAddAccount(BuildContext context) {
    PageTransitions.slideFade(context, const ProviderSelectionPage());
  }

  void _navigateToEditAccount(BuildContext context, ImapConfig config) {
    PageTransitions.slideFade(
      context,
      ImapConfigPage(config: config, isEditMode: true),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ImapConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除邮箱'),
        content: Text('确定要删除 ${config.email} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(accountConfigProvider.notifier).deleteConfig(config.id);
      // 删除成功后用户可以看到列表变化，无需额外通知
    }
  }
}

/// 邮箱账户列表项组件
class _AccountListItem extends StatelessWidget {
  const _AccountListItem({
    required this.config,
    required this.onEdit,
    required this.onDelete,
  });

  final ImapConfig config;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: AppEdgeInsets.card,
          child: Row(
            children: [
              // 邮箱图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.mail, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),

              // 邮箱信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.displayName ?? config.email,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config.email,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${config.server}:${config.port}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // 操作按钮
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.iconPrimary),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 12),
                        Text('删除', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
