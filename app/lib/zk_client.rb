# frozen_string_literal: true
require "net/http"
require "uri"
require "date"

# ZkClient — talks to a ZKTeco "ZK Web Server" time-attendance terminal over HTTP.
#
# Verified endpoints (firmware: "ZK Web Server", Secutime 2006-2009):
#   GET  /                -> sets Set-Cookie: SessionID=...
#   POST /csl/check       -> body username=<id>&userpwd=<pwd>  (marks session logged-in)
#   GET  /csl/download    -> list page with user checkboxes (name=uid value=NN), paginated
#   POST /form/Download   -> body sdate=YYYY-MM-DD&edate=YYYY-MM-DD&period=0&uid=..&uid=..
#                            returns attlog.dat (tab-separated: uid, name, "YYYY-MM-DD HH:MM:SS", s1, s2)
#
# Usage:
#   client = ZkClient.new(host: "192.168.10.15", username: "999", password: "999")
#   client.login
#   uids    = client.all_uids
#   records = client.records("2026-08-01", "2026-09-24")           # all users
#   records = client.records("2026-08-01", "2026-09-24", [1070])   # single user
class ZkClient
  Record = Struct.new(:uid, :name, :time, :s1, :s2, keyword_init: true)

  class Error < StandardError; end

  attr_reader :host, :port

  def initialize(host:, username:, password:, port: 80, open_timeout: 5, read_timeout: 30)
    @host = host
    @port = port
    @username = username.to_s
    @password = password.to_s
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @cookie = nil
  end

  # Establish a session and authenticate. Raises ZkClient::Error on failure.
  def login
    # 1) Touch root to receive a SessionID cookie.
    res = request(Net::HTTP::Get.new("/"))
    if (sc = res["set-cookie"]) && sc =~ /SessionID=([^;]+)/
      @cookie = "SessionID=#{$1}"
    end
    raise Error, "device did not issue a SessionID cookie" unless @cookie

    # 2) Submit credentials against the same session.
    check = Net::HTTP::Post.new("/csl/check")
    check.set_form_data(username: @username, userpwd: @password)
    request(check)

    # 3) Confirm authentication: an authed admin sees the real user list ("name=uid ...").
    #    Wrong credentials (or a non-admin user) get only a short redirect stub instead.
    probe = request(Net::HTTP::Get.new("/csl/download")).body.to_s
    unless probe.include?("name=uid")
      raise Error, "invalid Login ID / password, or this user is not an admin on the device"
    end
    true
  end

  # Every user id enrolled on the device (parsed across all pagination pages).
  def all_uids
    ensure_login
    uids = []
    ["/csl/download?last=20",
     "/csl/download?first=20&last=40",
     "/csl/download?first=41&last=80"].each do |path|
      body = request(Net::HTTP::Get.new(path)).body.to_s
      uids.concat(body.scan(/name=uid value=(\d+)/).flatten.map(&:to_i))
    end
    uids.uniq.sort
  end

  # User ids whose privilege on the device is an administrator role.
  # Row cells on /csl/user: checkbox | department | user id | name | card | group | privilege | option.
  def admin_uids
    ensure_login
    body = request(Net::HTTP::Get.new("/csl/user?first=0&last=1000")).body.to_s
    body.scan(/<tr.*?<\/tr>/m).filter_map do |tr|
      next unless tr.include?("name=uid")
      cells = tr.scan(/<td[^>]*>(.*?)<\/td>/m).flatten.map { |c| c.gsub(/<[^>]+>/, "").strip }
      cells[2].to_i if cells[2].to_s.match?(/\A\d+\z/) && cells[6].to_s.match?(/admin/i)
    end.uniq.sort
  end

  # Raw attlog.dat text for the given range/users.
  def download(sdate, edate, uids = nil)
    ensure_login
    uids ||= all_uids
    post = Net::HTTP::Post.new("/form/Download")
    # Net::HTTP#set_form_data can't repeat a key, so build the body by hand.
    body = "sdate=#{u(sdate)}&edate=#{u(edate)}&period=0" +
           uids.map { |id| "&uid=#{u(id)}" }.join
    post.body = body
    post["Content-Type"] = "application/x-www-form-urlencoded"
    request(post).body.to_s
  end

  # Parsed, sorted records. Pass a uid array for a single/subset export.
  def records(sdate, edate, uids = nil)
    parse(download(sdate, edate, uids))
      .sort_by { |r| [r.name.downcase, r.time] }
  end

  # uid => display name (prefers a real name over a numeric label).
  def users(sdate, edate)
    counts = Hash.new { |h, k| h[k] = Hash.new(0) }
    parse(download(sdate, edate)).each { |r| counts[r.uid][r.name] += 1 }
    counts.transform_values do |names|
      names.max_by { |name, n| [name =~ /\A\d+\z/ ? 0 : 1, n] }.first
    end
  end

  private

  def parse(text)
    text.each_line.filter_map do |line|
      f = line.chomp.split("\t")
      next if f.size < 3
      begin
        t = DateTime.strptime(f[2], "%Y-%m-%d %H:%M:%S").to_time
      rescue ArgumentError
        next
      end
      Record.new(uid: f[0].to_i, name: f[1], time: t, s1: f[3], s2: f[4])
    end
  end

  def ensure_login
    login unless @cookie
  end

  def request(req)
    req["Cookie"] = @cookie if @cookie
    http.request(req)
  rescue StandardError => e
    raise Error, "cannot reach device at #{@host}:#{@port} (#{e.class}: #{e.message})"
  end

  def http
    @http ||= begin
      h = Net::HTTP.new(@host, @port)
      h.open_timeout = @open_timeout
      h.read_timeout = @read_timeout
      h
    end
  end

  def u(v)
    URI.encode_www_form_component(v.to_s)
  end
end
