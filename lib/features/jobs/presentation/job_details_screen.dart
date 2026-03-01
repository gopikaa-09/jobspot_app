import 'package:flutter/material.dart';
import 'package:jobspot_app/core/theme/app_theme.dart';
import 'package:jobspot_app/data/services/application_service.dart';
import 'package:jobspot_app/data/services/job_service.dart';
import 'package:jobspot_app/features/jobs/presentation/create_job_screen.dart';
import 'package:jobspot_app/features/reviews/presentation/company_reviews_screen.dart';
import 'package:jobspot_app/data/services/report_service.dart';
import 'package:jobspot_app/core/utils/report_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jobspot_app/features/jobs/presentation/widgets/screening_dialog.dart';
import 'package:provider/provider.dart';
import 'package:jobspot_app/features/dashboard/presentation/providers/seeker_home_provider.dart';
import 'package:jobspot_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:jobspot_app/core/utils/job_match_helper.dart';

class JobDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  final String userRole;
  final bool isApplied;
  final VoidCallback? onApplied;
  final VoidCallback? onJobChanged;

  const JobDetailsScreen({
    super.key,
    required this.job,
    required this.userRole,
    this.isApplied = false,
    this.onApplied,
    this.onJobChanged,
  });

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen>
    with SingleTickerProviderStateMixin {
  final JobService _jobService = JobService();
  final ApplicationService _applicationService = ApplicationService();
  final ReportService _reportService = ReportService();

  late TabController _tabController;
  bool _isBookmarked = false;
  bool _isApplying = false;
  late bool _hasApplied;
  late Map<String, dynamic> _currentJob;

  @override
  void initState() {
    super.initState();
    _currentJob = Map.from(widget.job);
    _hasApplied = widget.isApplied;
    _tabController = TabController(length: 2, vsync: this);
    if (widget.userRole == 'seeker') {
      _checkSavedStatus();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkSavedStatus() async {
    final jobId = _currentJob['id'];
    if (jobId == null) return;
    try {
      final isSaved = await _jobService.isJobSaved(jobId);
      if (mounted) {
        setState(() => _isBookmarked = isSaved);
      }
    } catch (e) {
      debugPrint('Error checking saved status: $e');
    }
  }

  Future<void> _toggleSave() async {
    final jobId = _currentJob['id'];
    if (jobId == null) return;
    final previousStatus = _isBookmarked;
    setState(() => _isBookmarked = !previousStatus);

    // Optimistic update for provider
    if (widget.userRole == 'seeker') {
      try {
        context.read<SeekerHomeProvider>().toggleJobSaveLocally(
          jobId,
          _currentJob,
        );
      } catch (_) {}
    }

    try {
      await _jobService.toggleSaveJob(jobId, previousStatus);
    } catch (e) {
      if (mounted) {
        setState(() => _isBookmarked = previousStatus);
        // Revert provider
        if (widget.userRole == 'seeker') {
          try {
            context.read<SeekerHomeProvider>().toggleJobSaveLocally(
              jobId,
              _currentJob,
            );
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _applyJob() async {
    if (_isApplying || _hasApplied) return;

    List<String> questions = [];
    if (_currentJob['screening_questions'] != null) {
      questions = List<String>.from(_currentJob['screening_questions']);
    }

    String message =
        "Hi, I am interested in the ${_currentJob['title'] ?? 'this'} position. Please review my profile.";

    if (questions.isNotEmpty) {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ScreeningDialog(
          questions: questions,
          jobTitle: _currentJob['title'] ?? 'this',
        ),
      );
      if (result == null) {
        return; // dialog cancelled
      }
      message = result;
    }

    setState(() => _isApplying = true);

    // Optimistic update for provider
    if (widget.userRole == 'seeker') {
      try {
        // We might not have full provider here if pushed from a place without it, but usually yes
        context.read<SeekerHomeProvider>().markJobAsAppliedLocally(
          _currentJob['id'],
        );
      } catch (_) {}
    }

    try {
      await _applicationService.fastApply(
        jobPostId: _currentJob['id'],
        message: message,
      );
      if (mounted) {
        setState(() => _hasApplied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application sent successfully!')),
        );
      }
      widget.onApplied?.call();
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('offline_queued')) {
          setState(() => _hasApplied = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You are offline. Application queued and will be sent when connected!',
              ),
            ),
          );
          widget.onApplied?.call();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error applying for job: $e')));
        }
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _toggleJobStatus() async {
    final jobId = _currentJob['id'];
    if (jobId == null) return;
    final bool currentActive = _currentJob['is_active'] ?? true;
    final bool newStatus = !currentActive;
    try {
      await _jobService.updateJobStatus(jobId, newStatus);
      setState(() => _currentJob['is_active'] = newStatus);
      widget.onJobChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newStatus ? 'Job reopened' : 'Job closed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    }
  }

  void _shareJob() {
    final title = _currentJob['title'] ?? 'Job Opportunity';
    final company = _currentJob['company_name'] ?? 'Unknown Company';
    final location = _currentJob['location'] ?? 'Remote';
    final googleMapsUrl =
        "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location)}";

    final shareText =
        "Check out this job:\n\n$title at $company\nLocation: $location\n\nSee location on Maps: $googleMapsUrl";
    // ignore: deprecated_member_use
    Share.share(shareText);
  }

  Future<void> _openMap() async {
    final location = _currentJob['location'];
    if (location == null || location.isEmpty || location == 'Remote') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No specific location available')),
        );
      }
      return;
    }

    final uri = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location)}",
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not open maps')));
        }
      }
    } catch (e) {
      debugPrint('Error launching map: $e');
    }
  }

  void _navigateToEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateJobScreen(job: _currentJob),
      ),
    );
    if (result == true && mounted) {
      widget.onJobChanged?.call();
    }
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => ReportDialog(
        title: 'Report Job',
        reportTypes: const [
          'Fake Job',
          'Scam/Fraud',
          'Inappropriate Content',
          'Discriminatory',
          'Other',
        ],
        onSubmit: (type, description) async {
          await _reportService.reportJob(
            jobId: _currentJob['id'],
            reportType: type,
            description: description,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report submitted successfully')),
            );
          }
        },
      ),
    );
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmployer = widget.userRole == 'employer';
    final isActive = _currentJob['is_active'] ?? true;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280.0,
              backgroundColor: theme.scaffoldBackgroundColor,
              elevation: 0,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share_outlined),
                  ),
                  onPressed: _shareJob,
                ),
                if (!isEmployer && widget.userRole != 'admin')
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flag_outlined, color: Colors.red),
                    ),
                    onPressed: _showReportDialog,
                    tooltip: 'Report Job',
                  ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeaderContent(context),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.hintColor,
                    indicatorColor: theme.colorScheme.primary,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    tabs: const [
                      Tab(text: "Description"),
                      Tab(text: "Company"),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [_buildDescriptionTab(context), _buildCompanyTab(context)],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context, isEmployer, isActive),
    );
  }

  Widget _buildHeaderContent(BuildContext context) {
    final theme = Theme.of(context);
    final minPay = _currentJob['pay_amount_min'] ?? 0;
    final maxPay = _currentJob['pay_amount_max'];
    final salaryStr = maxPay != null ? '₹$minPay - ₹$maxPay' : '₹$minPay';
    final isSeeker = widget.userRole == 'seeker';

    int matchScore = 0;
    if (isSeeker) {
      final seekerProfile = context.read<ProfileProvider>().profileData;
      matchScore = JobMatchHelper.calculateMatchScore(
        seekerProfile,
        _currentJob,
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.business,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _currentJob['title'] ?? 'Position',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _currentJob['company_name'] ??
                        _currentJob['employer_profiles']?['company_name'] ??
                        _currentJob['employer']?['company_name'] ??
                        'Company Name',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.hintColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_currentJob['employer_profiles']?['is_verified'] == true ||
                    _currentJob['employer']?['is_verified'] == true) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, color: Colors.blue, size: 20),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTag(
                    context,
                    _currentJob['work_mode'] ?? 'Remote',
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildTag(
                    context,
                    _currentJob['type'] ?? 'Full Time',
                    Colors.purple,
                  ),
                  const SizedBox(width: 8),
                  _buildTag(context, salaryStr, Colors.green),
                ],
              ),
            ),
            if (isSeeker && matchScore > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$matchScore% Match',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildDescriptionTab(BuildContext context) {
    final theme = Theme.of(context);
    final requirements = _currentJob['requirements'] as List?;

    final salaryMin = _currentJob['pay_amount_min'] ?? 0;
    final salaryMax = _currentJob['pay_amount_max'];
    final salaryStr = salaryMax != null
        ? '₹$salaryMin - $salaryMax'
        : '₹$salaryMin';
    final rate = _currentJob['payment_rate'] ?? 'Month';

    final startTime =
        _currentJob['shift_start']?.toString().substring(0, 5) ?? '09:00';
    final endTime =
        _currentJob['shift_end']?.toString().substring(0, 5) ?? '18:00';
    final shiftStr = '$startTime - $endTime';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // New Overview Section
          Text(
            "Job Overview",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildOverviewCard(
                    context,
                    'Salary',
                    '$salaryStr / $rate',
                    Icons.currency_rupee_rounded,
                    Colors.green,
                  ),
                  _buildOverviewCard(
                    context,
                    'Type',
                    _currentJob['type'] ?? 'Full Time',
                    Icons.work_outline_rounded,
                    Colors.purple,
                  ),
                  _buildOverviewCard(
                    context,
                    'Shift',
                    shiftStr,
                    Icons.access_time_rounded,
                    Colors.orange,
                  ),
                  _buildOverviewCard(
                    context,
                    'Mode',
                    _currentJob['work_mode'] ?? 'On Site',
                    Icons.location_on_outlined,
                    Colors.blue,
                  ),
                  _buildOverviewCard(
                    context,
                    'Exp.',
                    _currentJob['experience_years'] ?? '0-1 Yrs',
                    Icons.timeline,
                    Colors.teal,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          Text(
            "About the Role",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentJob['description'] ?? 'No description.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 32),
          if (requirements != null && requirements.isNotEmpty) ...[
            Text(
              "Requirements",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...requirements.map(
              (req) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        req.toString(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_currentJob['assets'] != null &&
              (_currentJob['assets'] as List).isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              "Required Assets",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_currentJob['assets'] as List).map((asset) {
                return Chip(
                  label: Text(asset.toString()),
                  avatar: const Icon(Icons.check_circle, size: 16),
                  backgroundColor: theme.colorScheme.secondary.withValues(
                    alpha: 0.1,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: (MediaQuery.of(context).size.width - 64) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyTab(BuildContext context) {
    final theme = Theme.of(context);
    final isSeeker = widget.userRole == 'seeker';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  "Location",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on, color: theme.colorScheme.secondary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _currentJob['location'] ?? 'Remote',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Call Button
          SizedBox(
            width: double.infinity,
            child: _buildCallButton(context, isSeeker),
          ),
          const SizedBox(height: 16),
          // Directions Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map),
              label: const Text("Get Directions"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Reviews Section Entry
          InkWell(
            onTap: () {
              if (isSeeker) {
                final companyId = _currentJob['employer_id'];
                if (companyId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompanyReviewsScreen(
                        companyId: companyId,
                        companyName: _currentJob['company_name'] ?? 'Company',
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile unavailable')),
                  );
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.star, color: AppColors.sunny, size: 28),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Company Reviews",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSeeker ? "Tap to view ratings" : "View your ratings",
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isEmployer, bool isActive) {
    final theme = Theme.of(context);
    final isAdmin = widget.userRole == 'admin';
    final isSeeker = widget.userRole == 'seeker';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -5),
            blurRadius: 20,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (isAdmin) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        color: theme.disabledColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Admin View (Read Only)',
                        style: TextStyle(
                          color: theme.disabledColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (isSeeker) ...[
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: IconButton(
                  icon: Icon(
                    _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                    color: _isBookmarked
                        ? theme.colorScheme.secondary
                        : theme.iconTheme.color,
                  ),
                  onPressed: _toggleSave,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: (isActive && !_isApplying && !_hasApplied)
                      ? _applyJob
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                    ), // Taller button
                    backgroundColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isApplying
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _hasApplied
                              ? "Applied"
                              : isActive
                              ? "Apply Now"
                              : "Closed",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ] else if (isEmployer) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _navigateToEdit,
                  icon: const Icon(Icons.edit),
                  label: const Text("Edit Job"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleJobStatus,
                  icon: Icon(
                    isActive ? Icons.close : Icons.check,
                    color: Colors.white,
                  ),
                  label: Text(
                    isActive ? "Close Job" : "Reopen Job",
                    style: const TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive
                        ? theme.colorScheme.error
                        : Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton(BuildContext context, bool isSeeker) {
    if (!isSeeker) return const SizedBox.shrink();

    final employerProfile =
        _currentJob['employer_profiles'] as Map<String, dynamic>?;
    final contactMobile = employerProfile?['contact_mobile'] as String?;
    final hasPhone = contactMobile != null && contactMobile.isNotEmpty;

    return Tooltip(
      message: hasPhone ? 'Call Employer' : 'No mobile number provided',
      child: OutlinedButton.icon(
        onPressed: hasPhone
            ? () async {
                final uri = Uri.parse('tel:$contactMobile');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not launch dialer')),
                    );
                  }
                }
              }
            : null,
        icon: Icon(
          Icons.phone,
          color: hasPhone ? Theme.of(context).primaryColor : Colors.grey,
        ),
        label: Text(
          "Call Employer",
          style: TextStyle(
            color: hasPhone ? Theme.of(context).primaryColor : Colors.grey,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: hasPhone ? Theme.of(context).primaryColor : Colors.grey,
          ),
        ),
      ),
    );
  }
}
