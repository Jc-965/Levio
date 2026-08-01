import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_card.dart';
import '../singleton.dart';
import '../utils/haptic_utils.dart';

// Data models for community features
class CommunityPost {
  final String id;
  final String authorId;
  final String authorName;
  final String authorImage;
  String content;
  final DateTime timestamp;
  String? category;
  int likes;
  int commentCount;
  bool isLiked;
  final List<PostComment> comments;

  CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorImage,
    required this.content,
    required this.timestamp,
    this.category,
    this.likes = 0,
    this.commentCount = 0,
    this.isLiked = false,
    List<PostComment>? comments,
  }) : comments = comments ?? [];
}

class PostComment {
  final String id;
  final String authorName;
  final String authorImage;
  final String content;
  final DateTime timestamp;

  PostComment({
    required this.id,
    required this.authorName,
    required this.authorImage,
    required this.content,
    required this.timestamp,
  });
}

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxPostLength = 420;

  late TabController _tabController;
  final singleton = Singleton();
  List<CommunityPost> _posts = [];
  final TextEditingController _feedSearchController = TextEditingController();
  String _feedSearchQuery = '';
  String _feedFilterCategory = 'All';
  String _feedSortMode = 'Newest';
  bool _feedOnlyMine = false;
  Timer? _searchDebounce;
  int _postVersion = 0;
  int _visibleCachePostVersion = -1;
  String _visibleCacheSearchQuery = '';
  String _visibleCacheCategory = '';
  String _visibleCacheSortMode = '';
  bool _visibleCacheOnlyMine = false;
  List<CommunityPost> _visiblePostsCache = <CommunityPost>[];
  bool _isLoadingFeed = true;
  static const List<String> _postCategories = <String>[
    'General',
    'Exercise Tips',
    'Speech Therapy',
    'Daily Living',
    'Questions',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFeedData();
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is DateTime) return value;
    return DateTime.now();
  }

  List<CommunityPost> _postsFromRows(
    List<Map<String, dynamic>> rows,
    Set<String> blocked,
  ) {
    return rows
        .where((row) => !blocked.contains(row['user_id']?.toString()))
        .map(
          (row) => CommunityPost(
            id: row['id']?.toString() ?? '',
            authorId: row['user_id']?.toString() ?? '',
            authorName: row['user_name']?.toString() ?? 'Community Member',
            authorImage:
                row['profile_image']?.toString() ?? 'images/711128.png',
            content: row['content']?.toString() ?? '',
            timestamp: _parseTimestamp(row['created_at']),
            category: row['category']?.toString(),
            likes: (row['likes'] as num?)?.toInt() ?? 0,
            commentCount: (row['comment_count'] as num?)?.toInt() ?? 0,
            isLiked: row['liked_by_me'] == true,
          ),
        )
        .toList();
  }

  Future<void> _loadFeedData() async {
    if (!mounted) return;
    // Cache-first: returning to the tab renders the hydrated cache
    // immediately and refreshes quietly, instead of a spinner and a lost
    // scroll position on every visit.
    final cached = singleton.communityPosts;
    if (cached.isNotEmpty && _posts.isEmpty) {
      final blocked = await singleton.blockedUserIds();
      if (!mounted) return;
      setState(() {
        _posts = _postsFromRows(
          cached.map((row) => Map<String, dynamic>.from(row)).toList(),
          blocked,
        );
        _postVersion++;
        _isLoadingFeed = false;
      });
    } else {
      setState(() => _isLoadingFeed = true);
    }

    try {
      final rawPosts = await singleton.loadCommunityPosts(limit: 100);
      final blocked = await singleton.blockedUserIds();
      final posts = _postsFromRows(rawPosts, blocked);

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _postVersion++;
        _isLoadingFeed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingFeed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to load community feed right now.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
  }

  Future<void> _refreshFeed() async {
    await _loadFeedData();
  }

  void _showFeedSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Future<void> _reportPost(CommunityPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Report Post'),
        content: const Text(
          'Report this post to the ParkiWell team? Posts reported by '
          'several members are hidden automatically pending review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final reported = await singleton.reportCommunityPost(post.id);
    if (!mounted) return;
    _showFeedSnack(
      reported
          ? 'Thanks for the report. Our team will review this post.'
          : singleton.consumeLastCommunityError() ?? 'Unable to report post.',
    );
  }

  Future<void> _blockAuthor(CommunityPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Hide all posts and comments from ${post.authorName}? You can '
          'change this later from this menu on any of their posts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await singleton.blockCommunityUser(post.authorId);
    if (!mounted) return;
    setState(() {
      _posts.removeWhere((p) => p.authorId == post.authorId);
      _postVersion++;
    });
    _showFeedSnack('You will no longer see posts from ${post.authorName}.');
  }

  Future<void> _sharePost(CommunityPost post) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: '${post.content}\n\nShared from ParkiWell Community'),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to share this post right now.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
  }

  Future<void> _openExternalResource({
    required String title,
    required String url,
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: mode);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unable to open $title right now.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Future<void> _openHelplineResource() async {
    const number = '+18004734636';
    final callUri = Uri.parse('tel:$number');
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
      return;
    }

    await _openExternalResource(
      title: 'Helpline',
      url: 'https://www.parkinson.org/resources-support',
    );
  }

  Future<void> _loadCommentsForPost(CommunityPost post) async {
    final rawComments = await singleton.loadCommunityComments(post.id);
    final blocked = await singleton.blockedUserIds();
    final mapped = rawComments
        .where((row) => !blocked.contains(row['user_id']?.toString()))
        .map((row) {
          return PostComment(
            id: row['id']?.toString() ?? '',
            authorName: row['user_name']?.toString() ?? 'Member',
            authorImage:
                row['profile_image']?.toString() ?? 'images/711128.png',
            content: row['content']?.toString() ?? '',
            timestamp: _parseTimestamp(row['created_at']),
          );
        })
        .toList();

    if (!mounted) return;
    setState(() {
      post.comments
        ..clear()
        ..addAll(mapped);
      post.commentCount = mapped.length;
      _postVersion++;
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _feedSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openCommentsSheet(CommunityPost post) async {
    await _loadCommentsForPost(post);
    if (!mounted) return;
    _showCommentsSheet(post);
  }

  Future<void> _openCreatePostPage() async {
    HapticUtils.lightImpact();
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const _CreatePostScreen(),
      ),
    );
    if (created == true && mounted) {
      await _loadFeedData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Post shared'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
  }

  bool _isOwnPost(CommunityPost post) {
    final uid = singleton.cloudSessionUserId;
    if (uid == null || uid.isEmpty) return false;
    return post.authorId == uid;
  }

  List<CommunityPost> get _visiblePosts {
    if (_visibleCachePostVersion == _postVersion &&
        _visibleCacheSearchQuery == _feedSearchQuery &&
        _visibleCacheCategory == _feedFilterCategory &&
        _visibleCacheSortMode == _feedSortMode &&
        _visibleCacheOnlyMine == _feedOnlyMine) {
      return _visiblePostsCache;
    }

    var results = List<CommunityPost>.from(_posts);

    if (_feedOnlyMine) {
      results = results.where(_isOwnPost).toList();
    }

    if (_feedFilterCategory != 'All') {
      results = results
          .where((post) => (post.category ?? 'General') == _feedFilterCategory)
          .toList();
    }

    final query = _feedSearchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      results = results.where((post) {
        final content = post.content.toLowerCase();
        final author = post.authorName.toLowerCase();
        final category = (post.category ?? '').toLowerCase();
        return content.contains(query) ||
            author.contains(query) ||
            category.contains(query);
      }).toList();
    }

    switch (_feedSortMode) {
      case 'Oldest':
        results.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case 'Most Liked':
        results.sort((a, b) => b.likes.compareTo(a.likes));
        break;
      case 'Most Discussed':
        results.sort((a, b) => b.commentCount.compareTo(a.commentCount));
        break;
      default:
        results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
    }

    _visibleCachePostVersion = _postVersion;
    _visibleCacheSearchQuery = _feedSearchQuery;
    _visibleCacheCategory = _feedFilterCategory;
    _visibleCacheSortMode = _feedSortMode;
    _visibleCacheOnlyMine = _feedOnlyMine;
    _visiblePostsCache = results;
    return results;
  }

  void _showEditPostSheet(CommunityPost post) {
    final colors = context.colors;
    final textController = TextEditingController(text: post.content);
    String? selectedCategory = post.category;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Edit Post',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _postCategories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final category = _postCategories[index];
                      final isSelected = selectedCategory == category;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticUtils.selectionClick();
                          setModalState(() => selectedCategory = category);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected
                                  ? colors.primary
                                  : colors.border,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            category,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : colors.textSecondary,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  maxLength: _maxPostLength,
                  decoration: InputDecoration(
                    hintText: 'Update your post...',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final updatedContent = textController.text.trim();
                          if (updatedContent.isEmpty) return;

                          final messenger = ScaffoldMessenger.of(context);
                          final success = await singleton.updateCommunityPost(
                            postId: post.id,
                            content: updatedContent,
                            category: selectedCategory,
                          );
                          if (!mounted || !ctx.mounted) return;
                          if (!success) {
                            final error =
                                singleton.consumeLastCommunityError() ??
                                'Unable to update post.';
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(error),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            );
                            _showCrisisSupportIfNeeded(messenger);
                            return;
                          }

                          setState(() {
                            post.content = updatedContent;
                            post.category = selectedCategory;
                            _postVersion++;
                          });

                          _showCrisisSupportIfNeeded(messenger);
                          Navigator.pop(ctx);
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('Post updated'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeletePostDialog(CommunityPost post) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Post'),
          content: Text(
            'Delete this post permanently?',
            style: Theme.of(
              ctx,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final deleted = await singleton.deleteCommunityPost(post.id);
                if (!mounted) return;
                if (!deleted) {
                  final error =
                      singleton.consumeLastCommunityError() ??
                      'Unable to delete post.';
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(error),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  );
                  return;
                }

                setState(() {
                  _posts.removeWhere((p) => p.id == post.id);
                  _postVersion++;
                });
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('Post deleted'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: colors.primary,
            indicatorWeight: 2,
            labelColor: colors.textPrimary,
            unselectedLabelColor: colors.textTertiary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Feed'),
              Tab(text: 'Resources'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildFeedTab(colors), _buildResourcesTab(colors)],
          ),
        ),
      ],
    );
  }

  bool _isDefaultAvatar(String imagePath) {
    return imagePath.isEmpty ||
        imagePath == 'images/711128.png' ||
        imagePath.contains('711128');
  }

  Widget _buildAvatar({
    required String imagePath,
    required String fallbackLabel,
    required double size,
    required Color backgroundColor,
    required Color textColor,
  }) {
    final isDefault = _isDefaultAvatar(imagePath);
    if (isDefault) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: backgroundColor,
        child: Text(
          fallbackLabel,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.4,
          ),
        ),
      );
    }

    if (imagePath.startsWith('images/')) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: backgroundColor,
        child: ClipOval(
          child: Image.asset(
            imagePath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Center(
              child: Text(
                fallbackLabel,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.4,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Never open arbitrary file paths delivered in server rows: only the
    // device owner's own stored photo may be read from disk. Anything else
    // renders as initials.
    if (imagePath != singleton.image) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: backgroundColor,
        child: Center(
          child: Text(
            fallbackLabel,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.4,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: Image.file(
          File(imagePath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              fallbackLabel,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedTab(AppColors colors) {
    final visiblePosts = _visiblePosts;

    return RefreshIndicator(
      onRefresh: _refreshFeed,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search, write button, filters and sort all scroll away with the
          // feed so posts get the full screen while browsing.
          SliverToBoxAdapter(child: _buildFeedControls(colors)),
          if (_isLoadingFeed)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
            )
          else if (_posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyFeedState(colors),
            )
          else if (visiblePosts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildNoResultsState(colors),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 48),
              sliver: SliverList.separated(
                itemCount: visiblePosts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) =>
                    _buildPostCard(visiblePosts[index], colors),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostAuthorAvatar(
    CommunityPost post,
    double size,
    AppColors colors,
  ) {
    final fallback = post.authorName.isNotEmpty
        ? post.authorName[0].toUpperCase()
        : 'U';
    return _buildAvatar(
      imagePath: post.authorImage,
      fallbackLabel: fallback,
      size: size,
      backgroundColor: colors.primary.withValues(alpha: 0.1),
      textColor: colors.primary,
    );
  }

  Widget _buildCommentAuthorAvatar(
    PostComment comment,
    double size,
    AppColors colors,
  ) {
    final fallback = comment.authorName.isNotEmpty
        ? comment.authorName[0].toUpperCase()
        : 'U';
    return _buildAvatar(
      imagePath: comment.authorImage,
      fallbackLabel: fallback,
      size: size,
      backgroundColor: colors.surfaceVariant,
      textColor: colors.textSecondary,
    );
  }

  Widget _buildFeedControls(AppColors colors) {
    final categories = <String>['All', ..._postCategories];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _feedSearchController,
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 160),
                      () {
                        if (!mounted) return;
                        setState(() => _feedSearchQuery = value);
                      },
                    );
                  },
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: colors.textTertiary,
                      size: 18,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: colors.surfaceVariant.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _feedSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colors.textTertiary,
                            ),
                            onPressed: () {
                              _feedSearchController.clear();
                              setState(() {
                                _feedSearchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Write a post',
                child: GestureDetector(
                  onTap: _openCreatePostPage,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.primaryLight, colors.primary],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = _feedFilterCategory == category;
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selectionClick();
                    setState(() => _feedFilterCategory = category);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary
                          : colors.surfaceVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : colors.border.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      category,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected
                            ? colors.textOnPrimary
                            : colors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  setState(() => _feedSortMode = value);
                },
                offset: const Offset(0, 36),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'Newest', child: Text('Newest')),
                  PopupMenuItem(value: 'Oldest', child: Text('Oldest')),
                  PopupMenuItem(value: 'Most Liked', child: Text('Most Liked')),
                  PopupMenuItem(
                    value: 'Most Discussed',
                    child: Text('Most Discussed'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _feedSortMode,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                toggled: _feedOnlyMine,
                label: _feedOnlyMine ? 'Showing my posts' : 'Showing all posts',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticUtils.selectionClick();
                    setState(() => _feedOnlyMine = !_feedOnlyMine);
                  },
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _feedOnlyMine ? 'My posts' : 'All posts',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _feedOnlyMine
                            ? colors.primary
                            : colors.textTertiary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 36,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              'No posts match your filters',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another search, category, or sort option.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFeedState(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Be the first to share something with the community.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openCreatePostPage,
              child: const Text('Create Post'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(CommunityPost post, AppColors colors) {
    return ModernCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row
          Row(
            children: [
              _buildPostAuthorAvatar(post, 44, colors),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTimestamp(post.timestamp),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.category != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    post.category!,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (_isOwnPost(post))
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                  tooltip: 'Post options',
                  onSelected: (value) {
                    if (value == 'edit') {
                      HapticUtils.lightImpact();
                      _showEditPostSheet(post);
                      return;
                    }
                    if (value == 'delete') {
                      HapticUtils.lightImpact();
                      _showDeletePostDialog(post);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                )
              else
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                  tooltip: 'Post options',
                  onSelected: (value) {
                    if (value == 'report') {
                      HapticUtils.lightImpact();
                      _reportPost(post);
                      return;
                    }
                    if (value == 'block') {
                      HapticUtils.lightImpact();
                      _blockAuthor(post);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Text('Report post'),
                    ),
                    PopupMenuItem<String>(
                      value: 'block',
                      child: Text('Block user'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Content
          Text(
            post.content,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),

          // Actions row
          Row(
            children: [
              _buildActionButton(
                icon: post.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                label: post.likes.toString(),
                semanticLabel: post.isLiked
                    ? 'Unlike, ${post.likes} likes'
                    : 'Like, ${post.likes} likes',
                color: post.isLiked ? colors.error : colors.textSecondary,
                onTap: () async {
                  // Tolerant toggle: a second tap unlikes instead of
                  // scolding, which matters for tremor-induced double taps.
                  final wasLiked = post.isLiked;
                  HapticUtils.success();
                  final changed = wasLiked
                      ? await singleton.unlikeCommunityPost(post.id)
                      : await singleton.likeCommunityPost(post.id);
                  if (!mounted) return;
                  if (changed) {
                    setState(() {
                      post.isLiked = !wasLiked;
                      post.likes = wasLiked
                          ? (post.likes > 0 ? post.likes - 1 : 0)
                          : post.likes + 1;
                      _postVersion++;
                    });
                  } else {
                    final error =
                        singleton.consumeLastCommunityError() ??
                        'Unable to update like.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 28),
              _buildActionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: post.commentCount.toString(),
                semanticLabel: 'Comments, ${post.commentCount}',
                color: colors.textSecondary,
                onTap: () => _openCommentsSheet(post),
              ),
              const SizedBox(width: 28),
              _buildActionButton(
                icon: Icons.share_outlined,
                label: 'Share',
                semanticLabel: 'Share post',
                color: colors.textSecondary,
                onTap: () async {
                  HapticUtils.lightImpact();
                  await _sharePost(post);
                },
              ),
            ],
          ),

          // Show preview of comments if any
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: colors.divider),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _openCommentsSheet(post),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCommentAuthorAvatar(post.comments.first, 28, colors),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      // RichText defaults to no scaling; honor the user's
                      // system text size like every other Text in the app.
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: '${post.comments.first.authorName} ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: post.comments.first.content,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (post.comments.length > 1)
              GestureDetector(
                onTap: () => _openCommentsSheet(post),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.only(top: 8),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'View all ${post.comments.length} comments',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required String semanticLabel,
  }) {
    // 48px minimum tap target for tremor-friendly interaction
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCommentsSheet(CommunityPost post) {
    final colors = context.colors;
    final commentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Comments',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: post.comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No comments yet',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Be the first to comment!',
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: post.comments.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final comment = post.comments[index];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCommentAuthorAvatar(comment, 36, colors),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          comment.authorName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatTimestamp(comment.timestamp),
                                          style: TextStyle(
                                            color: colors.textTertiary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comment.content,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              // Comment input
              Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentController,
                        decoration: InputDecoration(
                          hintText: 'Write a comment...',
                          hintStyle: TextStyle(color: colors.textTertiary),
                          filled: true,
                          fillColor: colors.surfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        final comment = commentController.text.trim();
                        if (comment.isEmpty) return;
                        final messenger = ScaffoldMessenger.of(context);
                        HapticUtils.success();
                        final success = await singleton.createCommunityComment(
                          postId: post.id,
                          content: comment,
                        );
                        if (!mounted || !ctx.mounted) return;
                        if (!success) {
                          final errorMessage =
                              singleton.consumeLastCommunityError() ??
                              'Unable to add comment.';
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(errorMessage),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          );
                          _showCrisisSupportIfNeeded(messenger);
                          return;
                        }

                        await _loadCommentsForPost(post);
                        if (!mounted || !ctx.mounted) return;
                        setModalState(() {});
                        commentController.clear();
                        _showCrisisSupportIfNeeded(messenger);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResourcesTab(AppColors colors) {
    final resources = [
      {
        'icon': Icons.article_outlined,
        'title': 'Latest Research',
        'subtitle': 'Recent studies and findings',
        'url': 'https://www.parkinson.org/research',
      },
      {
        'icon': Icons.video_library_outlined,
        'title': 'Educational Videos',
        'subtitle': 'Learn about symptom management',
        'url': 'https://www.powerforparkinsons.org/youtube',
      },
      {
        'icon': Icons.local_hospital_outlined,
        'title': 'Find Specialists',
        'subtitle': 'Connect with movement disorder experts',
        'url': 'https://www.parkinson.org/living-with-parkinsons/finding-care',
      },
      {
        'icon': Icons.event_outlined,
        'title': 'Events Calendar',
        'subtitle': 'Webinars, support groups & meetups',
        'url': 'https://www.parkinson.org/events',
      },
      {
        'icon': Icons.phone_outlined,
        'title': 'Helpline',
        'subtitle': '24/7 support available',
        'action': 'helpline',
      },
      {
        'icon': Icons.menu_book_outlined,
        'title': 'Daily Living Guides',
        'subtitle': 'Daily living resources',
        'url': 'https://www.parkinson.org/living-with-parkinsons',
      },
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        ...resources.map(
          (resource) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ModernCard(
              onTap: () async {
                HapticUtils.lightImpact();
                final action = resource['action'] as String?;
                if (action == 'helpline') {
                  await _openHelplineResource();
                  return;
                }
                final url = resource['url'] as String?;
                if (url == null || url.isEmpty) return;
                await _openExternalResource(
                  title: resource['title'] as String,
                  url: url,
                );
              },
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    resource['icon'] as IconData,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resource['title'] as String,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          resource['subtitle'] as String,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}

/// Shows crisis support resources if the last community action detected
/// crisis language. The content itself is never blocked for this; we only
/// make sure the author sees where to get help.
void _showCrisisSupportIfNeeded(ScaffoldMessengerState messenger) {
  final support = Singleton().consumeLastCommunitySupportMessage();
  if (support == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(support),
      duration: const Duration(seconds: 10),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}

class _CreatePostScreen extends StatefulWidget {
  const _CreatePostScreen();

  @override
  State<_CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<_CreatePostScreen> {
  final singleton = Singleton();
  final TextEditingController _controller = TextEditingController();
  String? _selectedCategory;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty ||
        content.length > _CommunityScreenState._maxPostLength ||
        _submitting) {
      return;
    }

    setState(() => _submitting = true);
    HapticUtils.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    final success = await singleton.createCommunityPost(
      content: content,
      category: _selectedCategory ?? 'General',
    );
    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _submitting = false);
      final errorMessage =
          singleton.consumeLastCommunityError() ?? 'Unable to share post.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
    _showCrisisSupportIfNeeded(messenger);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canPost = _controller.text.trim().isNotEmpty && !_submitting;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.textPrimary),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Create Post',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: canPost ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                disabledBackgroundColor: colors.primary.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Post',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Category',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _CommunityScreenState._postCategories.map((category) {
                  final isSelected = _selectedCategory == category;
                  return GestureDetector(
                    onTap: () {
                      HapticUtils.selectionClick();
                      setState(() => _selectedCategory = category);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.primary : colors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isSelected ? colors.primary : colors.border,
                        ),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : colors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  maxLength: _CommunityScreenState._maxPostLength,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText:
                        'Share your thoughts, experience, or questions...',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    filled: true,
                    fillColor: colors.surface,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: colors.primary),
                    ),
                    counterStyle: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.textTertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
