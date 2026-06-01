import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/email_list_state.dart';
import '../shared/providers/email_list_provider.dart';
import '../shared/routes/animated_page_route.dart';
import '../widgets/swipeable_email_list_item.dart';
import 'email_detail_page.dart';
import '../features/account/pages/account_list_page.dart';
import '../features/account/pages/provider_selection_page.dart';
import '../features/settings/pages/api_key_config_page.dart';
import '../shared/themes/app_colors.dart';
import '../shared/themes/app_text_styles.dart';
import '../shared/themes/app_spacing.dart';

/// 邮件列表页面
///
/// 展示邮件列表，支持下拉刷新、上拉加载更多
/// 集成 EmailListProvider 进行状态管理
/// 集成 WidgetsBindingObserver 监听应用生命周期，实现前台自动刷新
class EmailListPage extends ConsumerStatefulWidget {
  const EmailListPage({super.key});

  @override
  ConsumerState<EmailListPage> createState() => _EmailListPageState();
}

/// EmailListPage 的状态类
class _EmailListPageState extends ConsumerState<EmailListPage>
    with WidgetsBindingObserver {
  /// 滚动控制器，用于监听滚动位置实现上拉加载更多
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // 初始化滚动控制器
    _scrollController = ScrollController();
    // 添加滚动监听
    _scrollController.addListener(_onScroll);

    // 注册应用生命周期监听
    WidgetsBinding.instance.addObserver(this);

    // 在下一帧加载邮件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeEmails();
    });
  }

  /// 初始化邮件列表
  ///
  /// 如果已初始化，直接显示缓存并后台静默刷新
  /// 如果未初始化，显示加载状态并加载
  void _initializeEmails() {
    final emailListState = ref.read(emailListProvider);

    if (emailListState.isInitialized) {
      // 已初始化，后台静默刷新
      ref.read(emailListProvider.notifier).silentRefresh();
    } else {
      // 未初始化，首次加载
      ref.read(emailListProvider.notifier).loadEmails();
    }
  }

  /// 从子页面返回时静默刷新邮件列表
  void _onReturnFromSubPage() {
    if (!mounted) return;
    final emailListState = ref.read(emailListProvider);
    if (emailListState.isInitialized &&
        !emailListState.isRefreshing &&
        !emailListState.isLoading) {
      ref.read(emailListProvider.notifier).silentRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用回到前台时，静默刷新邮件列表
    if (state == AppLifecycleState.resumed) {
      final emailListState = ref.read(emailListProvider);
      if (emailListState.isInitialized &&
          !emailListState.isRefreshing &&
          !emailListState.isLoading) {
        ref.read(emailListProvider.notifier).silentRefresh();
      }
    }
  }

  @override
  void dispose() {
    // 移除应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    // 移除滚动监听
    _scrollController.removeListener(_onScroll);
    // 释放滚动控制器
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听回调
  ///
  /// 当滚动到接近底部时，触发加载更多
  void _onScroll() {
    if (!mounted) return;
    // 如果滚动控制器没有附加到滚动视图，直接返回
    if (!_scrollController.hasClients) return;

    // 获取滚动位置和最大滚动范围
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // 当滚动到距离底部 200 像素时，触发加载更多
    // 这样可以提前加载，提升用户体验
    if (maxScroll - currentScroll <= 200) {
      ref.read(emailListProvider.notifier).loadMoreEmails();
    }
  }

  /// 处理下拉刷新
  ///
  /// 调用 EmailListProvider 的 refreshEmails 方法
  Future<void> _onRefresh() async {
    if (!mounted) return;
    try {
      await ref.read(emailListProvider.notifier).refreshEmails();
    } catch (e) {
      debugPrint('刷新邮件列表失败: $e');
    }
  }

  /// 处理列表项点击
  ///
  /// 导航到邮件详情页，返回时静默刷新列表
  Future<void> _onEmailTap(String emailId) async {
    if (!mounted) return;
    await PageTransitions.slideFade(
      context,
      EmailDetailPage(emailId: emailId),
    );
    _onReturnFromSubPage();
  }

  /// 处理重试
  ///
  /// 清除错误并重新加载邮件
  void _onRetry() {
    if (!mounted) return;
    ref.read(emailListProvider.notifier).loadEmails();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 监听邮件列表状态
    final emailListState = ref.watch(emailListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('邮件列表'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _onMenuSelected(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'accounts',
                child: Row(
                  children: [
                    Icon(Icons.mail, size: 20),
                    SizedBox(width: 12),
                    Text('我的邮箱'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_account',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, size: 20),
                    SizedBox(width: 12),
                    Text('添加邮箱'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'api_key',
                child: Row(
                  children: [
                    Icon(Icons.key_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('API Key 配置'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme, emailListState),
    );
  }

  /// 处理菜单选择
  Future<void> _onMenuSelected(String value) async {
    Widget? page;
    switch (value) {
      case 'accounts':
        page = const AccountListPage();
        break;
      case 'add_account':
        page = const ProviderSelectionPage();
        break;
      case 'api_key':
        page = const ApiKeyConfigPage();
        break;
    }
    if (page != null) {
      await PageTransitions.slideFade(context, page);
      _onReturnFromSubPage();
    }
  }

  /// 构建页面主体
  ///
  /// 根据状态显示不同的 UI：加载中、错误、空列表、正常列表
  Widget _buildBody(
    ThemeData theme,
    ColorScheme colorScheme,
    EmailListState emailListState,
  ) {
    // 1. 首次加载中（未初始化且正在加载）
    if (!emailListState.isInitialized && emailListState.isLoading) {
      return _buildLoadingIndicator(theme, colorScheme);
    }

    // 2. 错误状态（未初始化且有错误）
    if (!emailListState.isInitialized &&
        emailListState.error != null &&
        emailListState.emails.isEmpty) {
      return _buildErrorWidget(theme, colorScheme, emailListState.error!);
    }

    // 3. 空列表（已初始化但没有邮件）
    if (emailListState.isInitialized && emailListState.emails.isEmpty) {
      return _buildEmptyWidget(theme, colorScheme);
    }

    // 4. 正常列表（带下拉刷新）
    return _buildEmailList(emailListState, colorScheme);
  }

  /// 构建骨架屏占位列表
  ///
  /// 显示灰色占位块模拟邮件列表加载状态，提升感知性能
  Widget _buildLoadingIndicator(ThemeData theme, ColorScheme colorScheme) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头像占位
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: 12),
              // 文本内容占位
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：发件人 + 时间
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.borderLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.borderLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 第二行：主题
                    Container(
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 第三行：预览
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建错误提示
  Widget _buildErrorWidget(
    ThemeData theme,
    ColorScheme colorScheme,
    String errorMessage,
  ) {
    return Center(
      child: Padding(
        padding: AppEdgeInsets.page,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空列表提示
  ///
  /// 显示图标、说明文字和检查新邮件按钮
  Widget _buildEmptyWidget(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: AppEdgeInsets.page,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: AppColors.textTertiary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              '暂无邮件',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '您的收件箱是空的，点击下方按钮检查新邮件',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('检查新邮件'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建邮件列表
  ///
  /// 使用 RefreshIndicator 实现下拉刷新
  /// 使用 ListView.builder 实现列表渲染
  /// 底部显示加载更多指示器
  Widget _buildEmailList(
    EmailListState emailListState,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: emailListState.emails.length + 1, // +1 用于底部加载指示器
        itemBuilder: (context, index) {
          // 如果是最后一项，显示加载更多指示器
          if (index == emailListState.emails.length) {
            return _buildLoadMoreIndicator(emailListState, colorScheme);
          }

          // 正常列表项
          final email = emailListState.emails[index];
          return SwipeableEmailListItem(
            email: email,
            onTap: () => _onEmailTap(email.id),
            onDeleteConfirm: () => _confirmDeleteEmail(context, email),
          );
        },
      ),
    );
  }

  /// 确认删除邮件
  ///
  /// 显示确认对话框，用户确认后执行删除
  Future<bool> _confirmDeleteEmail(BuildContext context, email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除邮件'),
        content: const Text('确定要删除这封邮件吗？此操作无法撤销。'),
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

    if (confirmed == true) {
      // 执行删除
      final success = await ref
          .read(emailListProvider.notifier)
          .deleteEmail(email.id);

      // 删除失败时显示错误提示
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除失败'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }

      return false; // 返回 false 因为已经手动处理了删除
    }

    return false;
  }

  /// 构建加载更多指示器
  ///
  /// 根据状态显示不同的 UI：加载中、没有更多数据
  Widget _buildLoadMoreIndicator(
    EmailListState emailListState,
    ColorScheme colorScheme,
  ) {
    // 如果正在加载更多，显示加载指示器
    if (emailListState.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('加载中...'),
            ],
          ),
        ),
      );
    }

    // 如果没有更多数据，显示提示
    if (!emailListState.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            '没有更多邮件了',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
        ),
      );
    }

    // 默认返回空 Widget
    return const SizedBox.shrink();
  }
}
