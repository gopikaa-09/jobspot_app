import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JobService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<PostgrestList> fetchJobs({
    String? searchQuery,
    String? location,
    bool? sameDayPay,
    bool? walkIn,
    String? payType,
    String? workMode,
    List<String>? workingDays,
    int page = 0,
    int pageSize = 10,
  }) async {
    var query = _client
        .from('job_posts')
        .select('*, employer_profiles(contact_mobile, is_verified)')
        .eq('is_active', true);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
        'title.ilike.%$searchQuery%,description.ilike.%$searchQuery%',
      );
    }

    if (location != null && location.isNotEmpty) {
      query = query.ilike('location', '%$location%');
    }

    if (sameDayPay != null) {
      query = query.eq('same_day_pay', sameDayPay);
    }

    if (walkIn != null) {
      query = query.eq('is_walk_in', walkIn);
    }

    if (payType != null) {
      query = query.eq('pay_type', payType);
    }

    if (workMode != null) {
      query = query.eq('work_mode', workMode);
    }

    if (workingDays != null && workingDays.isNotEmpty) {
      query = query.contains('working_days', workingDays);
    }

    final start = page * pageSize;
    final end = start + pageSize - 1;

    final bool isDefaultFeed =
        page == 0 &&
        (searchQuery == null || searchQuery.isEmpty) &&
        (location == null || location.isEmpty) &&
        sameDayPay == null &&
        walkIn == null &&
        payType == null &&
        workMode == null &&
        (workingDays == null || workingDays.isEmpty);

    try {
      final response = await query
          .order('created_at', ascending: false)
          .range(start, end);

      if (isDefaultFeed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_jobs_feed', jsonEncode(response));
      }

      return PostgrestList.from(response);
    } catch (e) {
      if (isDefaultFeed) {
        final prefs = await SharedPreferences.getInstance();
        final cachedStr = prefs.getString('cached_jobs_feed');
        if (cachedStr != null) {
          debugPrint('Offline: Returning cached default jobs feed.');
          final List<dynamic> decoded = jsonDecode(cachedStr);
          return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      rethrow;
    }
  }

  Future<PostgrestList> fetchEmployerJobs() async {
    final userId = _client.auth.currentUser!.id;

    try {
      final response = await _client
          .from('job_posts')
          .select()
          .eq('employer_id', userId)
          .order('created_at', ascending: false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_employer_jobs', jsonEncode(response));

      return PostgrestList.from(response);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('cached_employer_jobs');
      if (cachedStr != null) {
        debugPrint('Offline: Returning cached employer jobs.');
        final List<dynamic> decoded = jsonDecode(cachedStr);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchJobById(String jobId) async {
    final response = await _client
        .from('job_posts')
        .select(
          '*, employer_profiles(company_name, avatar_url, city, contact_mobile)',
        )
        .eq('id', jobId)
        .maybeSingle();
    return response;
  }

  Future<Map<String, dynamic>> createJobPost(PostgrestMap jobData) async {
    return await _client.from('job_posts').insert(jobData).select().single();
  }

  /// Updates an existing job post with the provided [jobId] and [jobData].
  Future<Map<String, dynamic>> updateJobPost(
    String jobId,
    PostgrestMap jobData,
  ) async {
    return await _client
        .from('job_posts')
        .update(jobData)
        .eq('id', jobId)
        .select()
        .single();
  }

  Future<List<Map<String, dynamic>>> fetchSavedJobs() async {
    final userId = _client.auth.currentUser!.id;
    final response = await _client
        .from('saved_jobs')
        .select(
          '*, job_posts(*, employer_profiles(contact_mobile))',
        ) // Nested fetch
        .eq('seeker_id', userId)
        .order('saved_at', ascending: false);
    return (response as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> toggleSaveJob(String jobId, bool isCurrentlySaved) async {
    final userId = _client.auth.currentUser!.id;
    if (isCurrentlySaved) {
      await _client
          .from('saved_jobs')
          .delete()
          .eq('seeker_id', userId)
          .eq('job_id', jobId);
    } else {
      await _client.from('saved_jobs').insert({
        'seeker_id': userId,
        'job_id': jobId,
      });
    }
  }

  Future<bool> isJobSaved(String jobId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final response = await _client
        .from('saved_jobs')
        .select()
        .eq('seeker_id', userId)
        .eq('job_id', jobId)
        .maybeSingle();
    return response != null;
  }

  Future<void> updateJobStatus(String jobId, bool newStatus) async {
    await _client
        .from('job_posts')
        .update({'is_active': newStatus})
        .eq('id', jobId);
  }
}
