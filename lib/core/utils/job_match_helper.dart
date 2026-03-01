class JobMatchHelper {
  /// Calculates a match percentage (0-100) between a seeker profile and a job post.
  ///
  /// Weights:
  /// - Skills Match (60%): Ratio of required skills present in seeker's skills
  /// - Job Type Match (20%): Exact match of preferred_job_type and job's type
  /// - Location/Mode Match (20%): Remote job OR matching lowercase city/location
  static int calculateMatchScore(
    Map<String, dynamic>? seekerProfile,
    Map<String, dynamic>? jobPost,
  ) {
    if (seekerProfile == null || jobPost == null) return 0;

    double skillScore = 0.0;
    double typeScore = 0.0;
    double locationScore = 0.0;
    double assetsScore = 0.0;

    // 1. Skills Match (40% weight) -> Changed from 60 to accomodate Assets
    final seekerSkillsRaw = seekerProfile['skills'];
    final jobSkillsRaw = jobPost['skills'];

    List<String> seekerSkills = [];
    if (seekerSkillsRaw is List) {
      seekerSkills = seekerSkillsRaw
          .map((e) => e.toString().toLowerCase().trim())
          .toList();
    }

    List<String> jobSkills = [];
    if (jobSkillsRaw is List) {
      jobSkills = jobSkillsRaw
          .map((e) => e.toString().toLowerCase().trim())
          .toList();
    }

    if (jobSkills.isNotEmpty) {
      int matchCount = 0;
      for (final skill in jobSkills) {
        if (seekerSkills.contains(skill)) {
          matchCount++;
        }
      }
      skillScore = (matchCount / jobSkills.length) * 40;
    } else {
      // If job has no specific skill requirements, give full points for this section
      skillScore = 40.0;
    }

    // 2. Job Type Match (20% weight)
    final seekerType = seekerProfile['preferred_job_type']
        ?.toString()
        .toLowerCase()
        .trim();
    final jobType = jobPost['type']?.toString().toLowerCase().trim();

    if (jobType != null && seekerType != null && jobType == seekerType) {
      typeScore = 20.0;
    } else if (jobType == null) {
      typeScore = 20.0;
    }

    // 3. Location / Work Mode Match (20% weight)
    final seekerCity = seekerProfile['city']?.toString().toLowerCase().trim();
    final jobLocation = jobPost['location']?.toString().toLowerCase().trim();
    final jobWorkMode = jobPost['work_mode']?.toString().toLowerCase().trim();

    if (jobWorkMode == 'remote') {
      locationScore = 20.0;
    } else if (seekerCity != null && jobLocation != null) {
      // Simple substring match for city in location string
      if (jobLocation.contains(seekerCity) ||
          seekerCity.contains(jobLocation)) {
        locationScore = 20.0;
      }
    } else if (jobLocation == null) {
      locationScore = 20.0;
    }

    // 4. Assets Match (20% weight)
    final seekerAssetsRaw = seekerProfile['assets'];
    final jobAssetsRaw = jobPost['assets'];

    List<String> seekerAssets = [];
    if (seekerAssetsRaw is List) {
      seekerAssets = seekerAssetsRaw
          .map((e) => e.toString().toLowerCase().trim())
          .toList();
    }

    List<String> jobAssets = [];
    if (jobAssetsRaw is List) {
      jobAssets = jobAssetsRaw
          .map((e) => e.toString().toLowerCase().trim())
          .toList();
    }

    if (jobAssets.isNotEmpty) {
      int matchCount = 0;
      for (final asset in jobAssets) {
        if (seekerAssets.contains(asset)) {
          matchCount++;
        }
      }
      assetsScore = (matchCount / jobAssets.length) * 20;
    } else {
      // If no assets required, get full points
      assetsScore = 20.0;
    }

    final totalScore = skillScore + typeScore + locationScore + assetsScore;
    return totalScore.round().clamp(0, 100);
  }
}
