# Firestore Schema (Authoritative)

## Users
- Collection: `users/{uid}`
  - Fields: `createdAt`, `lastActiveAt`, `stats` (xp, xpToday, level, etc.)
  - Subcollection `enrollments/{courseId}`
    - Fields: `courseId`, `lastLessonId`, `progress` (0-100), `status` (`in_progress`|`completed`), `startedAt`, `updatedAt`
  - Subcollection `progress/{courseId}/modules/{moduleId}/lessons/{lessonId}`
    - Aggregates lesson progress with `completedActivities`, `totalActivities`, `progress` (0-100), `completed` (bool), `completedAt` (timestamp when finished), `updatedAt`
    - Subcollection `activities/{activityId}` with `completed` (bool) and `completedAt`
  - Subcollection `attempts/{attemptId}`
    - Mirrors activity attempts with fields: `uid`, `courseId`, `moduleId`, `lessonId`, `activityId`, `activityType`/`type`, `score` (0-100 pct), `scoreRaw` (original value), `passed` (bool), `startedAt`, `finishedAt`, `createdAt`
  - Subcollections `tasks/`, `streaks/` retained as before

## Attempts (global)
- Collection: `attempts/{attemptId}`
  - Same payload as `users/{uid}/attempts/{attemptId}`
  - Used for admin analytics aggregation

## Courses
- Collection: `courses/{courseId}/modules/{moduleId}/lessons/{lessonId}/activities/{activityId}`
  - Activity definitions for rendering quizzes/dictations/practice. Attempts are nested as `attempts/{attemptId}` for activity-local history.

## Progress rollups
- Lesson/module/course progress are derived from user `progress` docs:
  - Module aggregates `completedLessons`, `completedActivities`, `totalLessons`, `totalActivities`, `progress` (0-100), `completed`, `completedAt`, `updatedAt`
  - Course aggregates `completedModules`, `completedActivities`, `totalModules`, `totalActivities`, `progress` (0-100), `completed`, `completedAt`, `updatedAt`
  - Enrollment documents mirror the course progress percentage and last visited lesson id for the home screen and admin analytics.
