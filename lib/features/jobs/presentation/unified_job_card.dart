import 'package:flutter/material.dart';
import 'package:jobspot_app/data/services/application_service.dart';
import 'package:jobspot_app/data/services/job_service.dart';
import 'package:jobspot_app/features/jobs/presentation/job_details_screen.dart';
import 'package:jobspot_app/features/jobs/presentation/create_job_screen.dart';
import 'package:jobspot_app/features/jobs/presentation/widgets/job_card_header.dart';
import 'package:jobspot_app/features/jobs/presentation/widgets/screening_dialog.dart';

import 'package:jobspot_app/features/jobs/presentation/widgets/job_card_salary_info.dart';
import 'package:provider/provider.dart';
import 'package:jobspot_app/features/dashboard/presentation/providers/seeker_home_provider.dart';
import 'package:jobspot_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:jobspot_app/core/utils/job_match_helper.dart';

enum JobCardRole { seeker, employer }

class UnifiedJobCard extends StatefulWidget {
  final Map<String, dynamic> job;
  final JobCardRole role;

  // Job Actions
  final bool showBookmark;
  final bool canApply;
  final VoidCallback? onApplied;

  // Employer specific
  final void Function(Map<String, dynamic>)? afterEdit;
  final VoidCallback? onClose;

  const UnifiedJobCard({
    super.key,
    required this.job,
    required this.role,
    this.showBookmark = true,
    this.canApply = true,
    this.onApplied,
    this.afterEdit,
    this.onClose,
  });

  @override
  State<UnifiedJobCard> createState() => _UnifiedJobCardState();
}

class _UnifiedJobCardState extends State<UnifiedJobCard> {
  bool _isBookmarked = false;
  bool _isApplying = false;
  final JobService _jobService = JobService();

  @override
  void initState() {
    super.initState();
    if (widget.role == JobCardRole.seeker) {
      _checkSavedStatus();
    }
  }

  Future<void> _checkSavedStatus() async {
    if (widget.job['id'] == null) return;
    final isSaved = await _jobService.isJobSaved(widget.job['id']);
    if (mounted) {
      setState(() => _isBookmarked = isSaved);
    }
  }

  Future<void> _toggleSave() async {
    final jobId = widget.job['id'];
    if (jobId == null) return;

    final previousStatus = _isBookmarked;
    setState(() => _isBookmarked = !previousStatus);

    try {
      if (widget.role == JobCardRole.seeker) {
        // Try to update provider locally
        try {
          context.read<SeekerHomeProvider>().toggleJobSaveLocally(
            jobId,
            widget.job,
          );
        } catch (_) {
          // Provider might not be available in all contexts, ignore
        }
      }

      await _jobService.toggleSaveJob(jobId, previousStatus);
    } catch (e) {
      if (mounted) {
        setState(() => _isBookmarked = previousStatus);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving job: $e')));

        // Revert provider if it was updated (optional, but good practice)
        if (widget.role == JobCardRole.seeker) {
          try {
            context.read<SeekerHomeProvider>().toggleJobSaveLocally(
              jobId,
              widget.job,
            );
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _applyJob() async {
    List<String> questions = [];
    if (widget.job['screening_questions'] != null) {
      questions = List<String>.from(widget.job['screening_questions']);
    }

    String message =
        "Hi, I am interested in the ${widget.job['title'] ?? 'this'} position. Please review my profile.";

    if (questions.isNotEmpty) {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ScreeningDialog(
          questions: questions,
          jobTitle: widget.job['title'] ?? 'this',
        ),
      );
      if (result == null) {
        return; // User cancelled
      }
      message = result;
    }

    setState(() => _isApplying = true);
    try {
      await ApplicationService().fastApply(
        jobPostId: widget.job['id'],
        message: message,
      );

      if (widget.role == JobCardRole.seeker) {
        try {
          context.read<SeekerHomeProvider>().markJobAsAppliedLocally(
            widget.job['id'],
          );
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application sent successfully!')),
        );
      }
      widget.onApplied?.call();
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('offline_queued')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You are offline. Application queued and will be sent when connected!',
              ),
            ),
          );
          // Still call onApplied so UI updates as if sent
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

  void _navigateToCreateJob() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateJobScreen(job: widget.job)),
    );
    if (result != null && result is Map<String, dynamic>) {
      widget.afterEdit?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEmployer = widget.role == JobCardRole.employer;
    final isActive = widget.job['is_active'] ?? true;

    // Calculate match score if seeker
    int matchScore = 0;
    if (!isEmployer) {
      final seekerProfile = context.read<ProfileProvider>().profileData;
      matchScore = JobMatchHelper.calculateMatchScore(
        seekerProfile,
        widget.job,
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => JobDetailsScreen(
              job: widget.job,
              userRole: isEmployer ? 'employer' : 'seeker',
              isApplied: !widget.canApply,
            ),
          ),
        ).then((_) {
          // Trigger refresh when returning from details screen
          // This ensures any changes (applied, saved) are reflected immediately
          widget.onApplied?.call();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with Icon, Title, Company
              JobCardHeader(
                job: widget.job,
                iconSize: isEmployer ? 32 : 24,
                trailing: isEmployer
                    ? _buildStatusBadge(isActive)
                    : (widget.showBookmark
                          ? IconButton(
                              icon: Icon(
                                _isBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_outline,
                                color: _isBookmarked
                                    ? colorScheme.secondary
                                    : null,
                              ),
                              onPressed: _toggleSave,
                            )
                          : null),
              ),
              const SizedBox(height: 12),

              // Chips Row: Type, Mode, Shift (if available)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    context,
                    widget.job['type'] ?? 'Full Time',
                    Icons.work_outline,
                  ),
                  _buildInfoChip(
                    context,
                    widget.job['work_mode'] ?? 'Remote',
                    Icons.location_on_outlined,
                  ),
                  if (widget.job['shift_start'] != null &&
                      widget.job['shift_end'] != null)
                    _buildInfoChip(
                      context,
                      _formatShift(
                        widget.job['shift_start'],
                        widget.job['shift_end'],
                      ),
                      Icons.access_time,
                    ),
                  if (!isEmployer && matchScore > 0)
                    _buildInfoChip(
                      context,
                      '$matchScore% Match',
                      Icons.auto_awesome,
                      colorOverride: Colors.green,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Footer: Pay and Action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: JobCardSalaryInfo(job: widget.job)),
                  if (isEmployer && widget.job['same_day_pay'] == true)
                    _buildSameDayPayBadge(colorScheme),
                  if (!isEmployer) _buildSeekerAction(colorScheme),
                ],
              ),
              if (isEmployer) ...[
                const Divider(height: 32),
                _buildEmployerActions(colorScheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'OPEN' : 'CLOSED',
        style: TextStyle(
          color: isActive ? Colors.green : Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSameDayPayBadge(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 14, color: colorScheme.secondary),
          const SizedBox(width: 4),
          const Text(
            'SAME DAY PAY',
            style: TextStyle(
              color: Color(
                0xFFE67E22,
              ), // colorScheme.secondary but more visible
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekerAction(ColorScheme colorScheme) {
    return ElevatedButton(
      onPressed: (widget.canApply && !_isApplying) ? _applyJob : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      ),
      child: _isApplying
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(widget.canApply ? "Apply" : "Applied"),
    );
  }

  Widget _buildEmployerActions(ColorScheme colorScheme) {
    final isActive = widget.job['is_active'] ?? true;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _navigateToCreateJob,
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Edit'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isActive ? widget.onClose : null,
            icon: Icon(isActive ? Icons.lock_outline : Icons.lock, size: 18),
            label: Text(isActive ? 'Close' : 'Reopen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive
                  ? colorScheme.error
                  : colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    String label,
    IconData icon, {
    Color? colorOverride,
  }) {
    final theme = Theme.of(context);

    // Determine color based on label content for a "pop" effect
    Color chipColor;

    if (colorOverride != null) {
      chipColor = colorOverride;
    } else {
      final lowerLabel = label.toLowerCase();
      if (lowerLabel.contains('remote')) {
        chipColor = Colors.green;
      } else if (lowerLabel.contains('time') || lowerLabel.contains('full')) {
        chipColor = Colors.blue;
      } else if (lowerLabel.contains('part') ||
          lowerLabel.contains('contract')) {
        chipColor = Colors.orange;
      } else {
        chipColor = Colors.purple;
      }
    }

    // Use playful pastel shades
    final bgColor = chipColor.withValues(alpha: 0.08); // Very light background
    final fgColor = chipColor.withValues(alpha: 0.8); // Stronger text

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        // No border for cleaner look, just color
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatShift(dynamic start, dynamic end) {
    if (start == null || end == null) return 'Shift';
    try {
      final s = start.toString().substring(0, 5);
      final e = end.toString().substring(0, 5);
      return '$s - $e';
    } catch (_) {
      return 'Shift';
    }
  }
}
