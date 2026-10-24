# frozen_string_literal: true

# Pulls attendance from the ZK device and stores it in Postgres.
# Employees are upserted by uid; punches are deduped on (employee_id, punched_at).
class SyncService
  def self.client
    AppSetting.current.zk_client(
      username: ENV.fetch("ZK_USER", "999"),
      password: ENV.fetch("ZK_PASS", "999")
    )
  end

  def initialize(client: self.class.client)
    @client = client
  end

  # Returns { employees:, punches_seen:, punches_added: }.
  def sync(sdate, edate)
    @client.login
    names   = @client.users(sdate, edate)   # uid => display name
    records = @client.records(sdate, edate) # all punches in range

    # Upsert employees.
    names.each do |uid, name|
      emp = Employee.find_or_initialize_by(uid: uid)
      emp.name = name unless emp.name_locked? # keep names edited in Settings
      emp.save! if emp.changed?
    end
    refresh_admin_flags
    refresh_device_status
    id_by_uid = Employee.pluck(:uid, :id).to_h

    # Upsert punches in batches (skip duplicates via the unique index).
    now = Time.current
    added = 0
    records.each_slice(500) do |slice|
      rows = slice.filter_map do |r|
        eid = id_by_uid[r.uid]
        next unless eid
        { employee_id: eid, punched_at: r.time, s1: r.s1, s2: r.s2,
          created_at: now, updated_at: now }
      end
      next if rows.empty?
      result = Punch.insert_all(rows, unique_by: %i[employee_id punched_at])
      added += result.rows.size
    end

    { employees: names.size, punches_seen: records.size, punches_added: added }
  end

  # Marks which employees are admins on the device (shown in Settings).
  # Best-effort: a failure here must not break the punch sync.
  def refresh_admin_flags
    admins = @client.admin_uids
    return if admins.empty?

    Employee.where(uid: admins).update_all(device_admin: true)
    Employee.where.not(uid: admins).update_all(device_admin: false)
  rescue ZkClient::Error => e
    Rails.logger.warn("admin flag refresh skipped: #{e.message}")
  end

  # Mirrors the machine's per-user Enable/Disable flag (Settings → Machine access).
  # Best-effort, like the admin flags: the SDK port may be busy or blocked.
  def refresh_device_status
    Employee.refresh_device_status!(AppSetting.current.zk_sdk_client.users)
  rescue ZkSdkClient::Error => e
    Rails.logger.warn("device status refresh skipped: #{e.message}")
  end
end
