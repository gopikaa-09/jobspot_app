import 'package:flutter/material.dart';
import 'package:jobspot_app/core/theme/app_theme.dart';
import 'package:jobspot_app/data/services/application_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:jobspot_app/features/reviews/presentation/seeker_reviews_screen.dart';
import 'package:jobspot_app/data/services/report_service.dart';
import 'package:jobspot_app/core/utils/report_dialog.dart';
import 'package:jobspot_app/core/utils/job_match_helper.dart';

class ApplicantProfileScreen extends StatefulWidget {
  final Map<String, dynamic> application;

  const ApplicantProfileScreen({super.key, required this.application});

  @override
  State<ApplicantProfileScreen> createState() => _ApplicantProfileScreenState();
}

class _ApplicantProfileScreenState extends State<ApplicantProfileScreen> {
  late String _currentStatus;
  bool _isUpdating = false;
  final ApplicationService _applicationService = ApplicationService();
  final ReportService _reportService = ReportService();

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.application['status'] ?? 'pending';
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      await _applicationService.updateApplicationStatus(
        applicationId: widget.application['id'],
        status: newStatus,
      );
      if (mounted) {
        setState(() => _currentStatus = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to ${newStatus.toUpperCase()}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showReportDialog() {
    final applicant = widget.application['applicant'] as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (context) => ReportDialog(
        title: 'Report User',
        reportTypes: const [
          'Harassment',
          'Spam',
          'Fraud',
          'Inappropriate Content',
          'Other',
        ],
        onSubmit: (type, description) async {
          await _reportService.reportUser(
            reportedUserId: applicant['user_id'],
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppColors.orange;
      case 'shortlisted':
        return AppColors.purple;
      case 'hired':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final applicant = widget.application['applicant'] as Map<String, dynamic>;
    final job = widget.application['job_posts'] as Map<String, dynamic>;
    final matchScore = JobMatchHelper.calculateMatchScore(applicant, job);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Applicant Profile'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showReportDialog,
            icon: const Icon(Icons.flag_outlined, color: Colors.red),
            tooltip: 'Report User',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SeekerReviewsScreen(
                    seekerId: applicant['user_id'],
                    seekerName: applicant['full_name'] ?? 'Candidate',
                    canWriteReview:
                        true, // Employer viewing applicant can write reviews
                  ),
                ),
              );
            },
            icon: const Icon(Icons.reviews_outlined),
            tooltip: 'Reviews & Rating',
          ),
          // Call Button
          Builder(
            builder: (context) {
              final phone = applicant['phone'];
              final hasPhone = phone != null && phone.toString().isNotEmpty;
              return IconButton(
                onPressed: hasPhone
                    ? () async {
                        final uri = Uri.parse('tel:$phone');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not launch dialer'),
                              ),
                            );
                          }
                        }
                      }
                    : null,
                icon: Icon(Icons.phone, color: hasPhone ? null : Colors.grey),
                tooltip: hasPhone ? 'Call Candidate' : 'No mobile provided',
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: applicant['avatar_url'] != null
                        ? CachedNetworkImageProvider(applicant['avatar_url'])
                        : null,
                    child: applicant['avatar_url'] == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    applicant['full_name'] ?? 'Anonymous',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applied for: ${job['title']}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  if (matchScore > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
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
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$matchScore% Match',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Status Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Application Status',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            _currentStatus,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _currentStatus.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(_currentStatus),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (_isUpdating)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_currentStatus != 'shortlisted')
                        OutlinedButton(
                          onPressed: _isUpdating
                              ? null
                              : () => _updateStatus('shortlisted'),
                          child: const Text('shortlisted'),
                        ),
                      if (_currentStatus != 'hired')
                        OutlinedButton(
                          onPressed: _isUpdating
                              ? null
                              : () => _updateStatus('hired'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                          ),
                          child: const Text('Hire'),
                        ),
                      if (_currentStatus != 'rejected')
                        OutlinedButton(
                          onPressed: _isUpdating
                              ? null
                              : () => _updateStatus('rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: const Text('Reject'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Professional Details
            Text('Professional Details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Education'),
              subtitle: Text(applicant['education_level'] ?? 'Not provided'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('Skills'),
              subtitle: Text(
                (applicant['skills'] as List?)?.join(', ') ?? 'Not provided',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (applicant['assets'] != null &&
                (applicant['assets'] as List).isNotEmpty)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Assets'),
                subtitle: Text((applicant['assets'] as List).join(', ')),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 24),

            // Contact Info
            Text('Contact Information', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: Text(applicant['email'] ?? 'No email provided'),
              contentPadding: EdgeInsets.zero,
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final email = applicant['email'];
                if (email != null) {
                  final uri = Uri.parse('mailto:$email');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('Phone'),
              subtitle: Text(applicant['phone']?.toString() ?? 'Not provided'),
              contentPadding: EdgeInsets.zero,
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final phone = applicant['phone'];
                if (phone != null) {
                  final uri = Uri.parse('tel:$phone');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Location'),
              subtitle: Text(applicant['city'] ?? 'Unknown location'),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 24),
            if (applicant['resume_url'] != null) ...[
              Text('Resume', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(applicant['resume_url']);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open resume')),
                      );
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: Colors.red),
                      const SizedBox(width: 12),
                      const Text('View Resume'),
                      const Spacer(),
                      const Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
