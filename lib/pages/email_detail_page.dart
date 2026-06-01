import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/email_detail_state.dart';
import '../shared/providers/email_detail_provider.dart';
import '../shared/providers/email_list_provider.dart';
import '../shared/themes/app_colors.dart';
import '../shared/themes/app_spacing.dart';
import '../shared/utils/date_utils.dart';
import '../features/content_rendering/widgets/content_renderer_widget.dart';
import '../features/content_rendering/widgets/message_viewer_widget.dart';
import '../shared/models/email.dart';
import '../features/email_parser/models/email_content_type.dart';

/// 邮件详情页面
///
/// 展示邮件的详细信息，包括发件人、主题、日期和内容
/// 使用 ContentRendererWidget 自动识别并渲染邮件内容
class EmailDetailPage extends ConsumerStatefulWidget {
  /// 邮件 ID
  final String emailId;

  const EmailDetailPage({super.key, required this.emailId});

  @override
  ConsumerState<EmailDetailPage> createState() => _EmailDetailPageState();
}

/// EmailDetailPage 的状态类
class _EmailDetailPageState extends ConsumerState<EmailDetailPage> {
  /// WebView 是否可见
  ///
  /// 用于在返回动画前隐藏 WebView，避免残影
  bool _isWebViewVisible = true;

  @override
  void initState() {
    super.initState();
    // 在下一帧加载邮件详情，避免在 build 期间修改状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(emailDetailProvider.notifier).loadEmailDetail(widget.emailId);
    });
  }

  /// 处理返回操作
  ///
  /// 先隐藏 WebView，再执行返回导航，避免残影
  Future<void> _handlePop() async {
    // 1. 先隐藏 WebView
    setState(() {
      _isWebViewVisible = false;
    });

    // 2. 等待 UI 更新
    await Future.delayed(const Duration(milliseconds: 50));

    // 3. 执行返回导航
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 处理重试
  ///
  /// 清除错误并重新加载邮件详情
  void _onRetry() {
    if (!mounted) return;
    ref.read(emailDetailProvider.notifier).loadEmailDetail(widget.emailId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 监听邮件详情状态
    final emailDetailState = ref.watch(emailDetailProvider);

    return PopScope(
      canPop: true, // 允许默认返回（包括手势返回）
      onPopInvokedWithResult: (didPop, result) {
        // 如果已经返回，重置状态
        if (didPop) {
          _isWebViewVisible = true;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('邮件详情'),
          centerTitle: true,
          backgroundColor: colorScheme.surface,
          surfaceTintColor: colorScheme.surfaceTint,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handlePop,
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _onMenuSelected(value, context),
              itemBuilder: (context) => [
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
                      Text('删除邮件', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _buildBody(theme, colorScheme, emailDetailState),
      ),
    );
  }

  /// 处理菜单选择
  void _onMenuSelected(String value, BuildContext context) {
    switch (value) {
      case 'delete':
        _confirmDeleteEmail(context);
        break;
    }
  }

  /// 确认删除邮件
  Future<void> _confirmDeleteEmail(BuildContext context) async {
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

    if (confirmed == true && context.mounted) {
      // 执行删除
      final success = await ref
          .read(emailListProvider.notifier)
          .deleteEmail(widget.emailId);

      if (context.mounted) {
        // 删除失败时显示错误提示
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('删除失败'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // 删除成功后返回上一页
          Navigator.of(context).pop();
        }
      }
    }
  }

  /// 构建页面主体
  ///
  /// 根据状态显示不同的 UI：加载中、错误、正常内容
  Widget _buildBody(
    ThemeData theme,
    ColorScheme colorScheme,
    EmailDetailState emailDetailState,
  ) {
    // 1. 错误状态
    if (emailDetailState.error != null) {
      return _buildErrorWidget(theme, colorScheme, emailDetailState.error!);
    }

    // 2. 邮件数据加载中
    if (emailDetailState.isLoading) {
      return _buildLoadingIndicator(theme, colorScheme);
    }

    // 3. 正常内容（可能还在渲染中，用 Visibility 控制）
    if (emailDetailState.email != null) {
      return Visibility(
        visible: !emailDetailState.isContentLoading,
        maintainState: true, // 保持状态，让内容组件继续加载
        child: _buildEmailContent(theme, colorScheme, emailDetailState.email!),
      );
    }

    // 4. 空状态（理论上不应该到达这里）
    return _buildEmptyWidget(theme, colorScheme);
  }

  /// 构建加载指示器
  Widget _buildLoadingIndicator(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在加载邮件详情...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyWidget(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.email_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '邮件不存在',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建邮件内容
  ///
  /// 包含邮件头部信息卡片和邮件正文
  Widget _buildEmailContent(ThemeData theme, ColorScheme colorScheme, Email email) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 邮件头部信息卡片
          _buildEmailHeader(theme, colorScheme, email),

          // 邮件正文
          _buildEmailBody(theme, colorScheme, email),
        ],
      ),
    );
  }

  /// 构建邮件头部信息
  ///
  /// 展示发件人、日期，使用浅灰背景卡片样式
  /// 参考 Obsidian 笔记属性的设计
  Widget _buildEmailHeader(ThemeData theme, ColorScheme colorScheme, Email email) {
    // 格式化日期为真实日期+时间
    final formattedDate = DateTimeUtils.formatDateTime(email.date);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5), // 浅灰背景
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 发件人
          _buildInfoRow(
            theme,
            colorScheme,
            '发件人',
            email.senderName?.isNotEmpty == true
                ? '${email.senderName} <${email.senderEmail}>'
                : email.senderEmail,
          ),
          const SizedBox(height: 8),

          // 日期
          _buildInfoRow(theme, colorScheme, '日期', formattedDate),
        ],
      ),
    );
  }

  /// 构建信息行
  ///
  /// 用于显示发件人、收件人、日期等信息
  Widget _buildInfoRow(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  /// 构建邮件正文
  ///
  /// 根据内容类型选择渲染方式：
  /// - Markdown 类型：使用 ContentRendererWidget（支持 Markdown 语法高亮）
  /// - HTML/纯文本类型：使用 MessageViewerWidget（官方 MimeMessageViewer）
  Widget _buildEmailBody(ThemeData theme, ColorScheme colorScheme, Email email) {
    // 内容加载完成回调
    void onContentReady() {
      if (!mounted) return;
      ref.read(emailDetailProvider.notifier).setContentLoading(false);
    }

    // 1. 如果是 Markdown 类型，使用 ContentRendererWidget
    if (email.contentType == EmailContentType.markdown) {
      if (email.body == null || email.body!.isEmpty) {
        return _buildEmptyContent(theme, colorScheme);
      }
      return Padding(
        padding: AppEdgeInsets.page,
        child: ContentRendererWidget(
          content: email.body!,
          contentType: email.contentType,
          backgroundColor: colorScheme.surface,
          padding: const EdgeInsets.zero,
          onContentReady: onContentReady,
        ),
      );
    }

    // 2. HTML 和纯文本类型，使用 MessageViewerWidget
    if (email.mimeMessageRaw != null && email.mimeMessageRaw!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MessageViewerWidget(
          mimeMessageRaw: email.mimeMessageRaw!,
          backgroundColor: colorScheme.surface,
          isVisible: _isWebViewVisible,
          onContentReady: onContentReady,
        ),
      );
    }

    // 3. 降级：使用 ContentRendererWidget
    if (email.body == null || email.body!.isEmpty) {
      onContentReady();
      return _buildEmptyContent(theme, colorScheme);
    }

    return Padding(
      padding: AppEdgeInsets.page,
      child: ContentRendererWidget(
        content: email.body!,
        contentType: email.contentType,
        backgroundColor: colorScheme.surface,
        padding: EdgeInsets.zero,
        onContentReady: onContentReady,
      ),
    );
  }

  /// 构建空内容提示
  Widget _buildEmptyContent(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: AppEdgeInsets.page,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '邮件内容为空',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
