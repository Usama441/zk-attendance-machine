# frozen_string_literal: true
require "socket"
require "timeout"

# ZkSdkClient — talks to the terminal's binary "standalone SDK" protocol (TCP 4370).
#
# Deactivation: this firmware has NO enforced per-user "disabled" flag. The privilege
# byte only carries the role in bits 1-3 (0 user, 14 super admin); setting bit 0 (the
# old "disabled bit") is ignored by the device, so such a user can still punch. The only
# thing the machine actually enforces is the absence of credentials, so to deactivate we
# remove every way the person can verify — fingerprints, password and card — and keep the
# rest of the record (ID, name, privilege). Reactivation cannot restore biometrics; the
# fingerprint must be re-enrolled at the machine.
#
# Speaks TCP, falling back to UDP. Verified on CL4000A / ZMM220_TFT, firmware "Ver 6.60 Sep 19 2019" (72-byte user records).
#
# Usage:
#   client = ZkSdkClient.new(host: "192.168.10.15", comm_key: 0)
#   client.users                      # => [DeviceUser, ...]
#   client.set_enabled("1070", false) # deactivate badge 1070
class ZkSdkClient
  class Error < StandardError; end

  DeviceUser = Struct.new(:uid, :user_id, :name, :privilege, keyword_init: true) do
    def enabled? = (privilege & 1).zero?
    def admin?   = (privilege & 0b1110) == 14
  end

  CMD_CONNECT      = 1000
  CMD_EXIT         = 1001
  CMD_REFRESHDATA  = 1013
  CMD_AUTH         = 1102
  CMD_PREPARE_DATA = 1500
  CMD_DATA         = 1501
  CMD_FREE_DATA    = 1502
  CMD_PREPARE_BUF  = 1503
  CMD_READ_BUF     = 1504
  CMD_USER_WRQ     = 8
  CMD_USERTEMP_RRQ = 9
  CMD_DELETE_USERTEMP       = 134
  CMD_DOWNLOAD_USERPHOTO    = 10_010
  FCT_USER         = 5
  FCT_FINGERTMP    = 2
  PASSWORD_OFFSET  = 3
  CARD_OFFSET      = 35
  CMD_ACK_OK       = 2000
  CMD_ACK_UNAUTH   = 2005
  USHRT_MAX        = 65_535
  TCP_MAGIC        = [0x5050, 0x7282].freeze
  RECORD_SIZE      = 72

  def initialize(host:, port: 4370, comm_key: 0, timeout: 10)
    @host = host
    @port = port
    @comm_key = comm_key.to_i
    @timeout = timeout
  end

  # Every user on the device.
  def users
    session { raw_users.map { |raw| decode(raw) } }
  end

  # Deactivate (enabled: false) removes every credential the person can verify with —
  # all fingerprint templates, the password and the card — while keeping their record
  # (ID, name, privilege) and history. A user with no credential cannot punch or open
  # the door, which is the only block this firmware enforces.
  #
  # Activate (enabled: true) cannot restore biometrics: the fingerprint must be
  # re-enrolled at the machine (Menu -> User Mng -> ID -> Edit). It only confirms the
  # record still exists and leaves it untouched; the caller tells the admin to re-enroll.
  #
  # Returns the user as re-read from the device afterwards.
  def set_enabled(user_id, enabled)
    session do
      raw = raw_users.find { |r| decode(r).user_id == user_id.to_s }
      raise Error, "user #{user_id} is not enrolled on the device" unless raw

      return decode(raw) if enabled

      iuid = decode(raw).uid
      delete_fingerprints(iuid, user_id)

      # Clear the password and card fields; keep everything else untouched.
      record = raw.dup
      record[PASSWORD_OFFSET, 8] = ("\x00".b * 8)
      record[CARD_OFFSET, 4]     = [0].pack("V")
      unless record == raw
        expect_ok(command(CMD_USER_WRQ, record), "clear credentials for user #{user_id}")
        expect_ok(command(CMD_REFRESHDATA), "refresh device data")
      end

      if fingerprint_count(iuid).positive?
        raise Error, "device did not remove the fingerprints for user #{user_id}"
      end

      decode(raw_users.find { |r| decode(r).user_id == user_id.to_s })
    end
  end

  # Rename one user (by badge / ID number). Only the 24-byte name field (offset 11)
  # changes; face, fingerprints, photo, card and privilege are untouched. Names
  # longer than 24 bytes are cut to fit. Returns the user as re-read from the device.
  def set_name(user_id, name)
    session do
      raw = raw_users.find { |r| decode(r).user_id == user_id.to_s }
      raise Error, "user #{user_id} is not enrolled on the device" unless raw

      record = raw.dup
      record[11, 24] = [bytes(name, 24)].pack("a24")
      unless record == raw
        expect_ok(command(CMD_USER_WRQ, record), "write user #{user_id}")
        expect_ok(command(CMD_REFRESHDATA), "refresh device data")
      end

      updated = raw_users.map { |r| decode(r) }.find { |u| u.user_id == user_id.to_s }
      raise Error, "device did not apply the new name for user #{user_id}" unless updated&.name == cstr(bytes(name, 24)).strip

      updated
    end
  end

  # Enroll a new normal (non-admin) user. Fingerprints/face are then registered on
  # the machine itself (Menu → User Mng → Edit user). The internal uid is the next
  # free slot; the group is copied from an existing user so it matches the device.
  # Returns the user as re-read from the device afterwards.
  def add_user(user_id:, name:, password: nil, card: nil)
    user_id = user_id.to_s
    session do
      existing = raw_users
      decoded = existing.map { |r| decode(r) }
      raise Error, "ID #{user_id} is already enrolled on the device" if decoded.any? { |u| u.user_id == user_id }

      uid = (decoded.map(&:uid).max || 0) + 1
      raise Error, "the device has no free user slot" if uid > USHRT_MAX

      group = existing.first ? existing.first.unpack("vCa8a24Vxa7").last : "1"
      record = [uid, 0, password.to_s, bytes(name, 24), card.to_i, group, user_id].pack("vCa8a24Vxa7xa24")
      expect_ok(command(CMD_USER_WRQ, record), "add user #{user_id}")
      expect_ok(command(CMD_REFRESHDATA), "refresh device data")

      added = raw_users.map { |r| decode(r) }.find { |u| u.user_id == user_id }
      raise Error, "device did not save user #{user_id}" unless added

      added
    end
  end

  # User photos stored on the machine (the face-enrollment photo, or one taken at
  # Menu → User Mng → Edit → Photo). Returns { "1100" => jpeg bytes }.
  # The device's own photo list (CMD_GET_ALLUSERPHOTO_LIST) misses most photos on this
  # firmware, so every enrolled user is asked for "<id>.jpg"; users without one get no JPEG back.
  def user_photos
    session do
      raw_users.map { |r| decode(r).user_id }.uniq.filter_map do |user_id|
        data = fetch(CMD_DOWNLOAD_USERPHOTO, "#{user_id}.jpg\x00")
        [user_id, data] if data.to_s.start_with?("\xFF\xD8".b)
      end.to_h
    end
  end

  private

  # A request whose reply is either inline (CMD_DATA) or streamed (CMD_PREPARE_DATA,
  # then CMD_DATA packets, then CMD_ACK_OK). Returns nil when the device has nothing.
  def fetch(cmd, payload = "".b)
    res = command(cmd, payload)
    case res[:code]
    when CMD_DATA then res[:data]
    when CMD_PREPARE_DATA
      want = res[:data].unpack1("V")
      data = +"".b
      loop do
        pkt = receive
        case pkt[:code]
        when CMD_DATA   then data << pkt[:data]
        when CMD_ACK_OK then break
        else raise Error, "unexpected reply #{pkt[:code]} while reading data"
        end
      end
      raise Error, "short read (#{data.bytesize}/#{want} bytes)" if data.bytesize < want

      data
    end
  end

  # Truncate to the field size without cutting a multi-byte character in half.
  def bytes(s, max)
    s = s.to_s.encode("UTF-8")
    s = s[0...-1] while s.bytesize > max
    s.b
  end

  def session
    connect
    yield
  ensure
    disconnect
  end

  # TCP first; the device allows only one TCP SDK client at a time and resets
  # the rest, so fall back to UDP (which it serves separately).
  def connect
    open_session(:tcp)
  rescue Error => e
    raise unless e.message.include?("stopped responding") || e.message.include?("cannot reach")

    disconnect
    open_session(:udp)
  end

  def open_session(transport)
    @udp = transport == :udp
    @sock = if @udp
              UDPSocket.new.tap { |u| u.connect(@host, @port) }
            else
              Timeout.timeout(@timeout) { TCPSocket.new(@host, @port) }
            end
    @session_id = 0
    @reply_id = USHRT_MAX - 1
    res = command(CMD_CONNECT)
    @session_id = res[:session]
    res = command(CMD_AUTH, commkey(@comm_key, @session_id)) if res[:code] == CMD_ACK_UNAUTH
    raise Error, "wrong Comm Key for the device (SDK auth refused)" if res[:code] == CMD_ACK_UNAUTH
    raise Error, "device refused SDK connection (code #{res[:code]})" unless res[:code] == CMD_ACK_OK
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "cannot reach device SDK at #{@host}:#{@port} (#{e.class}: #{e.message})"
  end

  def disconnect
    return unless @sock

    command(CMD_EXIT) rescue nil
    @sock.close rescue nil
    @sock = nil
  end

  # Delete every fingerprint template (finger slots 0-9) for one internal uid. Both the
  # internal-uid and badge-string request forms are sent per slot (firmwares differ on
  # which they accept); deleting an empty slot is harmless. The caller verifies the result
  # with fingerprint_count, so a wrong form fails loudly rather than silently.
  def delete_fingerprints(iuid, badge)
    (0..9).each do |finger|
      command(CMD_DELETE_USERTEMP, [badge.to_s, finger].pack("a24C"))
      command(CMD_DELETE_USERTEMP, [iuid, finger].pack("vC"))
    end
    expect_ok(command(CMD_REFRESHDATA), "refresh device data")
  end

  # Number of valid fingerprint templates currently stored for one internal uid.
  def fingerprint_count(iuid)
    data = read_buffer(CMD_USERTEMP_RRQ, FCT_FINGERTMP)
    return 0 if data.bytesize < 4

    total = data.unpack1("V")
    body = data.byteslice(4, total).to_s
    off = 0
    count = 0
    while off + 6 <= body.bytesize
      size, uid, _fid, valid = body.byteslice(off, 6).unpack("vvcc")
      break if size.nil? || size <= 6

      count += 1 if uid == iuid && valid != 0
      off += size
    end
    count
  end

  # Raw 72-byte user records.
  def raw_users
    data = read_buffer(CMD_USERTEMP_RRQ, FCT_USER)
    return [] if data.bytesize < 4

    total = data.unpack1("V")
    body = data.byteslice(4, total).to_s
    raise Error, "unsupported user record format (#{total} bytes)" unless (total % RECORD_SIZE).zero?

    (0...body.bytesize / RECORD_SIZE).map { |i| body.byteslice(i * RECORD_SIZE, RECORD_SIZE) }
  end

  # Layout: uid u16 | privilege u8 | password 8 | name 24 | card u32 | pad | group 7 | pad | user_id 24
  def decode(raw)
    uid, priv, _pwd, name, _card, _group, user_id = raw.unpack("vCa8a24Vxa7xa24")
    DeviceUser.new(uid: uid, privilege: priv, name: cstr(name).strip, user_id: cstr(user_id))
  end

  def cstr(s) = s.split("\x00", 2).first.to_s.force_encoding("UTF-8").scrub

  # Buffered read: ask the device to prepare the data, then pull it in chunks.
  def read_buffer(cmd, fct)
    res = command(CMD_PREPARE_BUF, [1, cmd, fct, 0].pack("cs<l<l<"))
    return res[:data] if res[:code] == CMD_DATA
    raise Error, "device cannot prepare user data (code #{res[:code]})" unless res[:code] == CMD_ACK_OK

    size = res[:data].byteslice(1, 4).unpack1("V")
    data = +"".b
    while data.bytesize < size
      chunk = [size - data.bytesize, @udp ? 16 * 1024 : 0xFFC0].min
      data << read_chunk(data.bytesize, chunk)
    end
    command(CMD_FREE_DATA)
    data
  end

  def read_chunk(start, size)
    res = command(CMD_READ_BUF, [start, size].pack("l<l<"))
    return res[:data] if res[:code] == CMD_DATA
    raise Error, "unexpected reply #{res[:code]} while reading data" unless res[:code] == CMD_PREPARE_DATA

    want = res[:data].unpack1("V")
    data = +"".b
    loop do
      pkt = receive
      case pkt[:code]
      when CMD_DATA   then data << pkt[:data]
      when CMD_ACK_OK then break
      else raise Error, "unexpected reply #{pkt[:code]} while reading data"
      end
    end
    raise Error, "short read (#{data.bytesize}/#{want} bytes)" if data.bytesize < want

    data
  end

  # The checksum covers the header with the *previous* reply id; the packet then
  # carries the incremented one. That is what the vendor SDK does and the device checks.
  def command(cmd, payload = "".b)
    sum = checksum([cmd, 0, @session_id, @reply_id].pack("v4") + payload.b)
    @reply_id += 1
    @reply_id -= USHRT_MAX if @reply_id >= USHRT_MAX
    packet = [cmd, sum, @session_id, @reply_id].pack("v4") + payload.b
    if @udp
      @sock.send(packet, 0)
    else
      @sock.write([*TCP_MAGIC, packet.bytesize].pack("vvV") + packet)
    end
    res = receive
    @reply_id = res[:reply]
    res
  end

  def receive
    body = @udp ? read_datagram : read_tcp_packet
    raise Error, "invalid packet from device" if body.bytesize < 8

    code, _sum, session, reply = body.unpack("v4")
    { code: code, session: session, reply: reply, data: body.byteslice(8..) }
  end

  def read_tcp_packet
    m1, m2, len = read_exact(8).unpack("vvV")
    raise Error, "invalid packet from device" unless [m1, m2] == TCP_MAGIC && len >= 8

    read_exact(len)
  end

  def read_datagram
    raise Error, "device stopped responding (UDP timeout)" unless IO.select([@sock], nil, nil, @timeout)

    @sock.recv(65_535)
  rescue SystemCallError => e
    raise Error, "device stopped responding (#{e.class})"
  end

  def read_exact(n)
    buf = +"".b
    Timeout.timeout(@timeout) do
      while buf.bytesize < n
        part = @sock.readpartial(n - buf.bytesize)
        buf << part
      end
    end
    buf
  rescue Timeout::Error, EOFError, SystemCallError => e
    raise Error, "device stopped responding (#{e.class})"
  end

  def expect_ok(res, what)
    raise Error, "device refused to #{what} (code #{res[:code]})" unless res[:code] == CMD_ACK_OK
  end

  # zkemsdk.c checksum: 16-bit words, wrapped by subtracting USHRT_MAX, then inverted.
  def checksum(bytes)
    sum = 0
    bytes.unpack("v*").each do |w|
      sum += w
      sum -= USHRT_MAX if sum > USHRT_MAX
    end
    sum += bytes.getbyte(-1) if bytes.bytesize.odd?
    sum -= USHRT_MAX while sum > USHRT_MAX
    sum = ~sum
    sum += USHRT_MAX while sum.negative?
    sum
  end

  # Scrambled Comm Key (ZK commpro.c MakeKey).
  def commkey(key, session_id, ticks = 50)
    k = 0
    32.times { |i| k = (k << 1) | (key[i]) }
    k = (k + session_id) & 0xFFFF_FFFF
    b = [k].pack("V").bytes.zip("ZKSO".bytes).map { |x, y| x ^ y }
    b = b[2, 2] + b[0, 2]
    t = ticks & 0xFF
    [b[0] ^ t, b[1] ^ t, t, b[3] ^ t].pack("C4")
  end
end
