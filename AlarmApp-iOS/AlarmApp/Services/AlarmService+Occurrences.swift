import Foundation
import SwiftData

/// 다음 기상 카드(메인)에 보여 줄 가장 가까운 실제 울림
struct NextWake: Equatable {
    var alarmID: UUID
    var title: String
    var fire: Date
    /// `.base`(기본 일정) 또는 `.changed`(이번만 변경)
    var state: Occurrence.State
    var mission: MissionType
    var memoText: String
    var memoRead: Bool
}

/// 이번만 변경(기획서 11.3)과 그에 따른 OS 예약 계획. 알람 변경의 단일 진입점 규칙은 그대로 `AlarmService`가 맡는다.
extension AlarmService {
    // MARK: 조회

    func exceptions(for alarm: Alarm) -> [DayExceptionValue] {
        let id = alarm.id
        return ((try? context.fetch(FetchDescriptor<DayException>(predicate: #Predicate { $0.alarmID == id }))) ?? []).map(\.value)
    }

    /// 앞으로 7일의 울림(요일순). 지난 회차는 없다. 목록과 OS 예약이 같은 계산을 쓴다.
    func upcomingOccurrences(for alarm: Alarm, now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        OccurrenceResolver.upcoming(schedule: alarm.schedule, exceptions: exceptions(for: alarm), now: now, calendar: calendar)
    }

    /// 켜진 알람 전체에서 가장 가까운 실제 울림. 퀵알람·미루기 재울림은 포함하지 않는다.
    func nextWake(now: Date = .now, calendar: Calendar = .current) -> NextWake? {
        let alarms = (try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.isEnabled }))) ?? []
        var best: NextWake?
        for alarm in alarms {
            for occurrence in upcomingOccurrences(for: alarm, now: now, calendar: calendar) {
                guard let fire = occurrence.fire, fire > now else { continue }
                if let best, best.fire <= fire { continue }
                let memo = EffectiveMemo.resolve(baseText: alarm.memoText, baseRead: alarm.memoReadEnabled, exception: occurrence.exception)
                best = NextWake(alarmID: alarm.id, title: alarm.title, fire: fire, state: occurrence.state,
                                mission: alarm.mission, memoText: memo.text, memoRead: memo.shouldRead)
            }
        }
        return best
    }

    // MARK: 변경

    /// 앞으로 7일 안의 한 회차를 이번만 변경한다. 예약에 실패하면 변경을 되돌리고 에러를 던진다.
    func setException(for alarm: Alarm, _ value: DayExceptionValue, now: Date = .now, calendar: Calendar = .current) async throws {
        var value = value
        value.memoText = value.memoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.memoText.count <= Self.maxMemoLength else { throw AlarmValidationError.memoTooLong(max: Self.maxMemoLength) }
        let others = exceptions(for: alarm).filter { $0.dayKey != value.dayKey }
        let selectable = OccurrenceResolver.upcoming(schedule: alarm.schedule, exceptions: others, now: now, calendar: calendar)
        guard selectable.contains(where: { $0.dayKey == value.dayKey && $0.baseFire > now }) else {
            throw AlarmValidationError.exceptionUnavailable
        }
        if value.kind == .change {
            guard OccurrenceResolver.isValidChange(value.hour, value.minute, on: value.dayKey, now: now, calendar: calendar) else {
                throw AlarmValidationError.invalidExceptionTime
            }
        }
        let alarmID = alarm.id, key = value.dayKey
        let existing = try context.fetch(FetchDescriptor<DayException>(predicate: #Predicate { $0.alarmID == alarmID && $0.dayKey == key })).first
        let previous = existing?.value
        if let existing { existing.value = value } else { context.insert(DayException(alarmID: alarmID, value: value, createdAt: now)) }
        try context.save()
        if value.kind == .skip { await clearSnoozes(forAlarm: alarmID, onDay: key, calendar: calendar) }
        guard alarm.isEnabled else { return }
        defer { refreshAuthorization() }
        do {
            try await applyPlan(for: alarm, now: now, calendar: calendar)
        } catch {
            // OS 예약이 안 됐으면 변경을 되돌려 저장 상태와 실제 예약이 어긋나지 않게 한다.
            if let existing, let previous { existing.value = previous } else if let created = try? context.fetch(FetchDescriptor<DayException>(predicate: #Predicate { $0.alarmID == alarmID && $0.dayKey == key })).first {
                context.delete(created)
            }
            try? context.save()
            try? await applyPlan(for: alarm, now: now, calendar: calendar)
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }

    /// 해당 날짜의 이번만 변경을 없애고 기본 규칙으로 돌아간다.
    func clearException(for alarm: Alarm, dayKey: Int, now: Date = .now, calendar: Calendar = .current) async throws {
        let alarmID = alarm.id
        let found = try context.fetch(FetchDescriptor<DayException>(predicate: #Predicate { $0.alarmID == alarmID && $0.dayKey == dayKey }))
        guard !found.isEmpty else { return }
        found.forEach(context.delete)
        try context.save()
        guard alarm.isEnabled else { return }
        defer { refreshAuthorization() }
        do {
            try await applyPlan(for: alarm, now: now, calendar: calendar)
        } catch {
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }

    // MARK: 예약 계획 적용

    /// 알람 하나의 OS 예약을 계획(`SchedulePlan`)에 맞춘다: 반복(예외 요일 제외) + 일회성 대체 예약.
    /// 지난 이번만 변경은 여기서 정리되어 그 요일이 반복으로 돌아온다. **울리는 중인 것은 건드리지 않는다.**
    func applyPlan(for alarm: Alarm, now: Date = .now, calendar: Calendar = .current) async throws {
        try purgeStaleExceptions(for: alarm, now: now, calendar: calendar)
        let plan = SchedulePlan.make(schedule: alarm.schedule, exceptions: exceptions(for: alarm), now: now, calendar: calendar)

        if plan.weeklyWeekdays.isEmpty {
            if !isRinging(alarm.id) { try await scheduler.cancel(id: alarm.id) }
        } else {
            let weekly = AlarmSchedule(hour: alarm.hour, minute: alarm.minute, weekdays: plan.weeklyWeekdays)
            try await scheduler.schedule(AlarmSnapshot(id: alarm.id, title: alarm.title, schedule: weekly,
                                                       mission: alarm.mission, soundID: alarm.soundID))
        }

        let alarmID = alarm.id
        let existing = try context.fetch(FetchDescriptor<OccurrenceRecord>(predicate: #Predicate { $0.alarmID == alarmID }))
        var keep = Set<UUID>()
        for shot in plan.shots {
            let match = existing.first { $0.dayKey == shot.dayKey && $0.role == shot.role }
            // 이미 지난 시각의 새 예약은 만들지 않는다(예약 불가). 기존 기록은 울리는 동안 id 매핑을 위해 둔다.
            guard shot.fireDate > now || match != nil else { continue }
            let record = match ?? OccurrenceRecord(alarmID: alarmID, dayKey: shot.dayKey, fireDate: shot.fireDate, role: shot.role)
            if match == nil { context.insert(record) }
            record.fireDate = shot.fireDate
            keep.insert(record.id)
            if shot.fireDate > now {
                try await scheduler.scheduleOnce(OneShotSnapshot(
                    id: record.id, kind: .occurrence(title: alarm.title, soundID: alarm.soundID), fireDate: shot.fireDate))
            }
        }
        for old in existing where !keep.contains(old.id) {
            if isRinging(old.id) { continue } // 울리는 동안은 id → 알람 매핑을 지우지 않는다
            let id = old.id
            context.delete(old)
            try? await scheduler.cancel(id: id)
        }
        try context.save()
    }

    /// 지난 회차·알람의 요일에서 빠진 날짜·7일 밖의 이번만 변경을 지운다.
    private func purgeStaleExceptions(for alarm: Alarm, now: Date, calendar: Calendar) throws {
        let alarmID = alarm.id
        let rows = try context.fetch(FetchDescriptor<DayException>(predicate: #Predicate { $0.alarmID == alarmID }))
        guard !rows.isEmpty else { return }
        let live = Set(OccurrenceResolver.upcoming(schedule: alarm.schedule, exceptions: rows.map(\.value), now: now, calendar: calendar).map(\.dayKey))
        let stale = rows.filter { !live.contains($0.dayKey) }
        guard !stale.isEmpty else { return }
        stale.forEach(context.delete)
        try context.save()
    }

    /// 알람이 꺼졌거나 삭제됐을 때: 일회성 대체 예약을 취소하고, 필요하면 이번만 변경도 지운다.
    func clearOccurrences(forAlarm alarmID: UUID, deleteExceptions: Bool) async {
        if let records = try? context.fetch(FetchDescriptor<OccurrenceRecord>(predicate: #Predicate { $0.alarmID == alarmID })), !records.isEmpty {
            let ids = records.map(\.id)
            records.forEach(context.delete)
            try? context.save()
            for id in ids { try? await scheduler.cancel(id: id) }
        }
        if deleteExceptions,
           let rows = try? context.fetch(FetchDescriptor<DayException>(predicate: #Predicate { $0.alarmID == alarmID })), !rows.isEmpty {
            rows.forEach(context.delete)
            try? context.save()
        }
    }

    /// 알람이 없거나 꺼진 알람의 대체 예약 기록을 지운다. (알람이 지워진 알람의 이번만 변경도 정리)
    func cleanUpOrphanOccurrences(enabledAlarmIDs: Set<UUID>) async throws {
        let records = try context.fetch(FetchDescriptor<OccurrenceRecord>())
        for record in records where !enabledAlarmIDs.contains(record.alarmID) {
            if isRinging(record.id) { continue }
            let id = record.id
            context.delete(record)
            try? await scheduler.cancel(id: id)
        }
        let allAlarmIDs = Set(try context.fetch(FetchDescriptor<Alarm>()).map(\.id))
        for row in try context.fetch(FetchDescriptor<DayException>()) where !allAlarmIDs.contains(row.alarmID) {
            context.delete(row)
        }
        try context.save()
    }

    /// 그날 안에 예약된 미루기가 있으면 취소한다(건너뛰기).
    func clearSnoozes(forAlarm alarmID: UUID, onDay dayKey: Int, calendar: Calendar) async {
        guard let records = try? context.fetch(FetchDescriptor<SnoozeRecord>(predicate: #Predicate { $0.alarmID == alarmID })) else { return }
        let sameDay = records.filter { DayKey.key(for: $0.fireDate, calendar: calendar) == dayKey }
        guard !sameDay.isEmpty else { return }
        let ids = sameDay.map(\.id)
        sameDay.forEach(context.delete)
        try? context.save()
        for id in ids { try? await scheduler.cancel(id: id) }
    }

    private func isRinging(_ id: UUID) -> Bool {
        ringing.alertingIDs.contains(id) || ringing.ringingAlarmID == id
    }
}
