import { randomUUID } from 'node:crypto';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { cert, getApp, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { z } from 'zod';

const WRITER_DEVICE_ID = 'mcp-server';
const PRIORITY = { none: 0, low: 1, medium: 2, high: 3 };
const PRIORITY_NAME = ['none', 'low', 'medium', 'high'];
const REPEAT_PATTERNS = [
  'Never', 'Daily', 'Weekdays', 'Weekly', 'Biweekly', 'Monthly', 'Yearly',
  'Every N Days', 'Every N Weeks', 'Every N Months', 'Custom Weekdays'
];
const REPEAT_END_OPTIONS = ['Never', 'On Date', 'After Count'];
const ALARM_SOUNDS = [
  'defaultRingtone', 'studioRadar', 'studioOpening', 'studioBeacon',
  'studioChimes', 'studioConstellation', 'studioRipples'
];

const dateString = z.string().refine((value) => !Number.isNaN(Date.parse(value)), 'Must be an ISO date/time');
const nullableDateString = z.union([dateString, z.null()]);
const nullableString = z.union([z.string(), z.null()]);
const minuteList = z.array(z.number().int().min(0).max(10080));
const weekdayList = z.array(z.number().int().min(1).max(7)).max(7);

const createScheduleShape = {
  title: z.string().trim().min(1).max(500),
  scheduled_at: dateString.describe('ISO 8601 date/time, for example 2026-11-14T18:00:00+05:30'),
  notes: z.string().max(5000).optional(),
  url: z.string().url().max(2000).optional(),
  time_zone: z.string().max(100).optional(),
  list_name: z.string().trim().min(1).max(200).optional(),
  tags: z.array(z.string().trim().min(1).max(100)).max(50).optional(),
  is_urgent: z.boolean().optional(),
  is_flagged: z.boolean().optional(),
  is_completed: z.boolean().optional(),
  priority: z.enum(['none', 'low', 'medium', 'high']).optional(),
  repeat_pattern: z.enum(REPEAT_PATTERNS).optional(),
  repeat_weekdays: weekdayList.optional(),
  repeat_interval: z.number().int().min(1).max(365).optional(),
  repeat_end_option: z.enum(REPEAT_END_OPTIONS).optional(),
  repeat_end_at: nullableDateString.optional(),
  repeat_end_count: z.number().int().min(0).max(10000).optional(),
  excluded_occurrence_dates: z.array(dateString).max(500).optional(),
  alert_delivery: z.enum(['push', 'alarm']).optional(),
  alarm_sound: z.enum(ALARM_SOUNDS).optional(),
  alarm_snooze_enabled: z.boolean().optional(),
  alarm_snooze_minutes: z.number().int().min(1).max(1439).optional(),
  early_reminder_minutes: z.number().int().min(0).max(10080).optional(),
  additional_reminder_minutes: minuteList.optional()
};

const updateScheduleShape = {
  schedule_id: z.string().uuid(),
  title: z.string().trim().min(1).max(500).optional(),
  scheduled_at: dateString.optional(),
  notes: nullableString.optional(),
  url: z.union([z.string().url().max(2000), z.null()]).optional(),
  time_zone: nullableString.optional(),
  list_name: z.string().trim().min(1).max(200).optional(),
  tags: z.array(z.string().trim().min(1).max(100)).max(50).optional(),
  is_urgent: z.boolean().optional(),
  is_flagged: z.boolean().optional(),
  is_completed: z.boolean().optional(),
  priority: z.enum(['none', 'low', 'medium', 'high']).optional(),
  repeat_pattern: z.enum(REPEAT_PATTERNS).optional(),
  repeat_weekdays: weekdayList.optional(),
  repeat_interval: z.number().int().min(1).max(365).optional(),
  repeat_end_option: z.enum(REPEAT_END_OPTIONS).optional(),
  repeat_end_at: nullableDateString.optional(),
  repeat_end_count: z.number().int().min(0).max(10000).optional(),
  excluded_occurrence_dates: z.array(dateString).max(500).optional(),
  alert_delivery: z.enum(['push', 'alarm']).optional(),
  alarm_sound: z.enum(ALARM_SOUNDS).optional(),
  alarm_snooze_enabled: z.boolean().optional(),
  alarm_snooze_minutes: z.number().int().min(1).max(1439).optional(),
  early_reminder_minutes: z.number().int().min(0).max(10080).nullable().optional(),
  additional_reminder_minutes: minuteList.optional()
};

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

function firestore() {
  const projectId = requiredEnv('FIREBASE_PROJECT_ID');
  const clientEmail = requiredEnv('FIREBASE_CLIENT_EMAIL');
  const privateKey = requiredEnv('FIREBASE_PRIVATE_KEY').replace(/\\n/g, '\n');
  const app = getApps().length
    ? getApp()
    : initializeApp({
        credential: cert({ projectId, clientEmail, privateKey }),
        projectId
      });
  return getFirestore(app, process.env.FIRESTORE_DATABASE_ID || 'schedulr');
}

function schedulesCollection(db) {
  return db.collection('users').doc(requiredEnv('SCHEDULR_USER_ID')).collection('schedules');
}

function timestampFrom(value, fieldName) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error(`${fieldName} must be a valid ISO date/time`);
  const millis = date.getTime();
  if (millis < -62135596800000 || millis > 253402300799000) {
    throw new Error(`${fieldName} is outside Firestore's supported timestamp range`);
  }
  return Timestamp.fromMillis(millis);
}

function iso(value) {
  if (!value) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string') return new Date(value).toISOString();
  return null;
}

function serializeSchedule(doc) {
  const data = doc.data() || {};
  const priorityRaw = Number.isInteger(data.priorityRaw) ? data.priorityRaw : 0;
  return {
    id: doc.id,
    title: data.title ?? null,
    notes: data.notes ?? null,
    url: data.urlString ?? null,
    scheduled_at: iso(data.scheduledDate),
    created_at: iso(data.createdAt),
    updated_at: iso(data.clientUpdatedAt) ?? iso(data.updatedAt),
    server_updated_at: iso(data.updatedAt),
    deleted_at: iso(data.deletedAt),
    is_soft_deleted: data.isSoftDeleted === true,
    is_completed: data.isCompleted === true,
    is_urgent: data.isUrgent === true,
    is_flagged: data.isFlagged === true,
    priority: PRIORITY_NAME[priorityRaw] ?? 'none',
    priority_raw: priorityRaw,
    repeat_pattern: data.repeatPatternRaw ?? 'Never',
    repeat_weekdays: data.repeatWeekdays ?? [],
    repeat_interval: data.repeatInterval ?? 1,
    repeat_end_option: data.repeatEndOptionRaw ?? 'Never',
    repeat_end_at: iso(data.repeatEndDate),
    repeat_end_count: data.repeatEndCount ?? 0,
    excluded_occurrence_dates: (data.excludedOccurrenceDates || []).map(iso),
    alert_delivery: data.alertDeliveryRaw ?? 'push',
    alarm_sound: data.alarmSoundRaw ?? 'defaultRingtone',
    alarm_snooze_enabled: data.alarmSnoozeEnabled !== false,
    alarm_snooze_minutes: data.alarmSnoozeMinutes ?? 10,
    early_reminder_minutes: data.earlyReminderMinutes ?? null,
    additional_reminder_minutes: data.additionalReminderMinutes ?? [],
    time_zone: data.timeZoneIdentifier ?? null,
    list_name: data.listName ?? 'Reminders',
    tags: data.tags ?? [],
    writer_device_id: data.writerDeviceID ?? data.lastModifiedDeviceID ?? null,
    sync_version: data.syncVersion ?? 0
  };
}

function textResult(payload, summary) {
  return {
    content: [{ type: 'text', text: summary ?? JSON.stringify(payload, null, 2) }],
    structuredContent: payload
  };
}

function toolError(message) {
  return { content: [{ type: 'text', text: message }], isError: true };
}

function scheduleDoc(db, scheduleId) {
  return schedulesCollection(db).doc(scheduleId);
}

async function listSchedules(args) {
  const db = firestore();
  const limit = Math.min(args.limit ?? 50, 200);
  let query = schedulesCollection(db).orderBy('scheduledDate');
  if (args.start) query = query.where('scheduledDate', '>=', timestampFrom(args.start, 'start'));
  if (args.end) query = query.where('scheduledDate', '<=', timestampFrom(args.end, 'end'));
  const snapshot = await query.limit(Math.max(limit * 4, 200)).get();
  const schedules = snapshot.docs
    .map(serializeSchedule)
    .filter((schedule) => args.include_deleted || !schedule.is_soft_deleted)
    .filter((schedule) => args.include_completed || !schedule.is_completed)
    .slice(0, limit);
  return textResult(
    { schedules, count: schedules.length },
    schedules.length
      ? `Found ${schedules.length} schedule(s):\n${schedules.map((s) => `- ${s.scheduled_at ?? 'unscheduled'} — ${s.title} (${s.id})`).join('\n')}`
      : 'No schedules found.'
  );
}

async function getSchedule(args) {
  const db = firestore();
  const doc = await scheduleDoc(db, args.schedule_id).get();
  if (!doc.exists) return toolError(`Schedule ${args.schedule_id} was not found.`);
  const schedule = serializeSchedule(doc);
  return textResult({ schedule }, `${schedule.title ?? 'Schedule'} — ${schedule.scheduled_at ?? 'unscheduled'}`);
}

async function createSchedule(args) {
  const db = firestore();
  const scheduleId = randomUUID();
  const now = Timestamp.now();
  const payload = {
    scheduleID: scheduleId,
    createdAt: now,
    updatedAt: FieldValue.serverTimestamp(),
    clientUpdatedAt: now,
    deletedAt: null,
    isSoftDeleted: false,
    lastModifiedDeviceID: WRITER_DEVICE_ID,
    writerDeviceID: WRITER_DEVICE_ID,
    syncVersion: 1,
    lastSyncedVersion: 0,
    conflictResolutionTag: null,
    title: args.title,
    notes: args.notes ?? null,
    urlString: args.url ?? null,
    scheduledDate: timestampFrom(args.scheduled_at, 'scheduled_at'),
    isUrgent: args.is_urgent ?? false,
    repeatPatternRaw: args.repeat_pattern ?? 'Never',
    repeatWeekdays: args.repeat_weekdays ?? [1, 2, 3, 4, 5, 6, 7],
    repeatInterval: args.repeat_interval ?? 1,
    repeatEndCount: args.repeat_end_count ?? 0,
    excludedOccurrenceDates: (args.excluded_occurrence_dates ?? []).map((value) => timestampFrom(value, 'excluded_occurrence_dates')),
    repeatEndOptionRaw: args.repeat_end_option ?? 'Never',
    repeatEndDate: args.repeat_end_at === null ? null : args.repeat_end_at ? timestampFrom(args.repeat_end_at, 'repeat_end_at') : null,
    alertDeliveryRaw: args.alert_delivery ?? 'push',
    alarmSoundRaw: args.alarm_sound ?? 'defaultRingtone',
    alarmSnoozeEnabled: args.alarm_snooze_enabled ?? true,
    alarmSnoozeMinutes: args.alarm_snooze_minutes ?? 10,
    earlyReminderMinutes: args.early_reminder_minutes ?? null,
    additionalReminderMinutes: args.additional_reminder_minutes ?? [],
    timeZoneIdentifier: args.time_zone ?? null,
    listName: args.list_name ?? 'Reminders',
    tags: args.tags ?? [],
    isFlagged: args.is_flagged ?? false,
    isCompleted: args.is_completed ?? false,
    priorityRaw: PRIORITY[args.priority ?? 'none']
  };
  await scheduleDoc(db, scheduleId).set(payload);
  const schedule = serializeSchedule(await scheduleDoc(db, scheduleId).get());
  return textResult({ schedule }, `Created schedule “${schedule.title}” for ${schedule.scheduled_at}.`);
}

async function updateSchedule(args) {
  const db = firestore();
  const ref = scheduleDoc(db, args.schedule_id);
  const doc = await ref.get();
  if (!doc.exists) return toolError(`Schedule ${args.schedule_id} was not found.`);

  const payload = {};
  if (args.title !== undefined) payload.title = args.title;
  if (args.notes !== undefined) payload.notes = args.notes;
  if (args.url !== undefined) payload.urlString = args.url;
  if (args.scheduled_at !== undefined) payload.scheduledDate = timestampFrom(args.scheduled_at, 'scheduled_at');
  if (args.is_urgent !== undefined) payload.isUrgent = args.is_urgent;
  if (args.is_flagged !== undefined) payload.isFlagged = args.is_flagged;
  if (args.is_completed !== undefined) payload.isCompleted = args.is_completed;
  if (args.priority !== undefined) payload.priorityRaw = PRIORITY[args.priority];
  if (args.repeat_pattern !== undefined) payload.repeatPatternRaw = args.repeat_pattern;
  if (args.repeat_weekdays !== undefined) payload.repeatWeekdays = args.repeat_weekdays;
  if (args.repeat_interval !== undefined) payload.repeatInterval = args.repeat_interval;
  if (args.repeat_end_option !== undefined) payload.repeatEndOptionRaw = args.repeat_end_option;
  if (args.repeat_end_at !== undefined) payload.repeatEndDate = args.repeat_end_at === null ? null : timestampFrom(args.repeat_end_at, 'repeat_end_at');
  if (args.repeat_end_count !== undefined) payload.repeatEndCount = args.repeat_end_count;
  if (args.excluded_occurrence_dates !== undefined) payload.excludedOccurrenceDates = args.excluded_occurrence_dates.map((value) => timestampFrom(value, 'excluded_occurrence_dates'));
  if (args.alert_delivery !== undefined) payload.alertDeliveryRaw = args.alert_delivery;
  if (args.alarm_sound !== undefined) payload.alarmSoundRaw = args.alarm_sound;
  if (args.alarm_snooze_enabled !== undefined) payload.alarmSnoozeEnabled = args.alarm_snooze_enabled;
  if (args.alarm_snooze_minutes !== undefined) payload.alarmSnoozeMinutes = args.alarm_snooze_minutes;
  if (args.early_reminder_minutes !== undefined) payload.earlyReminderMinutes = args.early_reminder_minutes;
  if (args.additional_reminder_minutes !== undefined) payload.additionalReminderMinutes = args.additional_reminder_minutes;
  if (args.time_zone !== undefined) payload.timeZoneIdentifier = args.time_zone;
  if (args.list_name !== undefined) payload.listName = args.list_name;
  if (args.tags !== undefined) payload.tags = args.tags;

  payload.updatedAt = FieldValue.serverTimestamp();
  payload.clientUpdatedAt = Timestamp.now();
  payload.lastModifiedDeviceID = WRITER_DEVICE_ID;
  payload.writerDeviceID = WRITER_DEVICE_ID;
  payload.syncVersion = FieldValue.increment(1);

  await ref.set(payload, { merge: true });
  const schedule = serializeSchedule(await ref.get());
  return textResult({ schedule }, `Updated schedule “${schedule.title ?? args.schedule_id}”.`);
}

async function deleteSchedule(args) {
  const db = firestore();
  const ref = scheduleDoc(db, args.schedule_id);
  const doc = await ref.get();
  if (!doc.exists) return toolError(`Schedule ${args.schedule_id} was not found.`);
  await ref.set({
    isSoftDeleted: true,
    deletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    clientUpdatedAt: Timestamp.now(),
    lastModifiedDeviceID: WRITER_DEVICE_ID,
    writerDeviceID: WRITER_DEVICE_ID,
    syncVersion: FieldValue.increment(1)
  }, { merge: true });
  return textResult({ id: args.schedule_id, deleted: true }, `Deleted schedule ${args.schedule_id}.`);
}

export function createSchedulrMcpServer() {
  const server = new McpServer({ name: 'schedulr', version: '1.0.0' });

  server.registerTool('list_schedules', {
    title: 'List schedules',
    description: 'List Schedulr events in an optional ISO date range.',
    inputSchema: {
      start: dateString.optional().describe('Optional inclusive start ISO date/time'),
      end: dateString.optional().describe('Optional inclusive end ISO date/time'),
      include_completed: z.boolean().optional(),
      include_deleted: z.boolean().optional(),
      limit: z.number().int().min(1).max(200).optional()
    }
  }, listSchedules);

  server.registerTool('get_schedule', {
    title: 'Get schedule',
    description: 'Fetch one Schedulr event by UUID.',
    inputSchema: { schedule_id: z.string().uuid() }
  }, getSchedule);

  server.registerTool('create_schedule', {
    title: 'Create schedule',
    description: 'Create a Schedulr event in the same Firestore schema the iOS app syncs.',
    inputSchema: createScheduleShape
  }, createSchedule);

  server.registerTool('update_schedule', {
    title: 'Update schedule',
    description: 'Edit fields on an existing Schedulr event by UUID.',
    inputSchema: updateScheduleShape
  }, updateSchedule);

  server.registerTool('delete_schedule', {
    title: 'Delete schedule',
    description: 'Soft-delete a Schedulr event so the iOS app removes it during sync.',
    inputSchema: { schedule_id: z.string().uuid() }
  }, deleteSchedule);

  return server;
}
