.pragma library
.import "Land.js" as Land

// ---------------------------------------------------------------------------
// Launch Library 2 parsing

var STATIONS = {
  "International Space Station": { key: "iss", norad: 25544, short: "ISS" },
  "Tiangong space station": { key: "css", norad: 48274, short: "Tiangong" }
}

function str(v) { return v === undefined || v === null ? "" : String(v) }

function parseIsoDuration(iso) {
  // P1DT2H3M4S → seconds. Negative durations ("-PT45M") are kept signed.
  var m = /^(-)?P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?)?$/.exec(str(iso))
  if (!m) return NaN
  var s = (+m[2] || 0) * 86400 + (+m[3] || 0) * 3600 + (+m[4] || 0) * 60 + (+m[5] || 0)
  return m[1] ? -s : s
}

function formatSeconds(sec) {
  sec = Math.abs(Math.round(sec))
  var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  return m + "m " + (sec % 60) + "s"
}

function formatDuration(iso) {
  var s = parseIsoDuration(iso)
  if (isNaN(s) || s === 0) return ""
  var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
  var parts = []
  if (d) parts.push(d + "d")
  if (h) parts.push(h + "h")
  if (m && !d) parts.push(m + "m")
  return parts.join(" ")
}

function countdown(netMs, nowMs) {
  if (isNaN(netMs)) return ""
  var diff = (netMs - nowMs) / 1000
  return (diff >= 0 ? "T-" : "T+") + formatSeconds(diff)
}

// Compact countdown for the bar: "2d", "5h 12m", "14:05".
function shortCountdown(netMs, nowMs) {
  var diff = Math.round((netMs - nowMs) / 1000)
  if (isNaN(diff) || diff < 0) return ""
  if (diff >= 86400) return Math.floor(diff / 86400) + "d " + Math.floor(diff % 86400 / 3600) + "h"
  if (diff >= 3600) return Math.floor(diff / 3600) + "h " + Math.floor(diff % 3600 / 60) + "m"
  var m = Math.floor(diff / 60), s = diff % 60
  return m + ":" + (s < 10 ? "0" : "") + s
}

// Coarse status bucket, used for colour and for "next launch" selection.
function statusKind(abbrev) {
  switch (str(abbrev)) {
    case "Go": return "go"
    case "Success": return "success"
    case "In Flight": return "flight"
    case "Hold": return "hold"
    case "Failure": case "Partial Failure": return "fail"
    default: return "tbd"   // TBD, TBC
  }
}

function crewFrom(list) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var c = list[i], a = c.astronaut || {}
    out.push({
      name: str(a.name),
      role: c.role ? str(c.role.role) : "",
      agency: a.agency ? str(a.agency.abbrev || a.agency.name) : "",
      nationality: a.nationality && a.nationality[0] ? str(a.nationality[0].nationality_name || a.nationality[0].name) : "",
      timeInSpace: formatDuration(a.time_in_space),
      flights: a.flights_count || 0
    })
  }
  return out
}

function parseLaunch(r) {
  var mission = r.mission || {}
  var rocket = r.rocket || {}
  var config = rocket.configuration || {}
  var pad = r.pad || {}
  var stage = rocket.spacecraft_stage && rocket.spacecraft_stage[0] ? rocket.spacecraft_stage[0] : null
  var provider = r.launch_service_provider || {}
  var orbit = mission.orbit || {}
  var name = str(r.name)
  var bar = name.indexOf(" | ")

  var vids = []
  var sortedVids = (r.vid_urls || []).slice().sort(function(a, b) { return (a.priority || 99) - (b.priority || 99) })
  for (var i = 0; i < sortedVids.length; i++) {
    var v = sortedVids[i]
    if (!v.url) continue
    vids.push({
      url: str(v.url),
      title: str(v.title) || str(v.url),
      publisher: str(v.publisher || v.source),
      live: v.live === true,
      official: v.type ? str(v.type.name).indexOf("Official") === 0 : false,
      start: Date.parse(v.start_time)
    })
  }

  var info = []
  for (var j = 0; j < (r.info_urls || []).length; j++) {
    var u = r.info_urls[j]
    if (u.url) info.push({ url: str(u.url), title: str(u.title) || str(u.source) || str(u.url) })
  }

  var timeline = []
  for (var k = 0; k < (r.timeline || []).length; k++) {
    var t = r.timeline[k]
    var off = parseIsoDuration(t.relative_time)
    if (!isNaN(off) && t.type) timeline.push({ label: str(t.type.abbrev), offset: off })
  }
  timeline.sort(function(a, b) { return a.offset - b.offset })

  var destination = stage ? str(stage.destination) : ""
  var station = STATIONS[destination] || null
  if (!station) {
    var text = (name + " " + str(mission.description)).toLowerCase()
    if (text.indexOf("international space station") >= 0 || /\biss\b/.test(text)) station = STATIONS["International Space Station"]
    else if (text.indexOf("tiangong") >= 0) station = STATIONS["Tiangong space station"]
  }

  return {
    id: str(r.id),
    name: name,
    rocketName: bar >= 0 ? name.slice(0, bar) : str(config.full_name || config.name),
    missionName: bar >= 0 ? name.slice(bar + 3) : str(mission.name || name),
    provider: str(provider.name),
    providerAbbrev: str(provider.abbrev || provider.name),
    net: Date.parse(r.net),
    netPrecision: r.net_precision ? str(r.net_precision.name) : "",
    windowStart: Date.parse(r.window_start),
    windowEnd: Date.parse(r.window_end),
    status: r.status ? str(r.status.abbrev) : "TBD",
    statusName: r.status ? str(r.status.name) : "",
    statusDescription: r.status ? str(r.status.description) : "",
    kind: statusKind(r.status ? r.status.abbrev : ""),
    probability: r.probability === null || r.probability === undefined ? -1 : r.probability,
    weatherConcerns: str(r.weather_concerns),
    webcastLive: r.webcast_live === true,
    padName: str(pad.name),
    location: pad.location ? str(pad.location.name) : "",
    padLat: parseFloat(pad.latitude),
    padLon: parseFloat(pad.longitude),
    orbitName: str(orbit.name),
    orbitAbbrev: str(orbit.abbrev),
    missionType: str(mission.type),
    description: str(mission.description),
    vids: vids,
    info: info,
    flightclub: str(r.flightclub_url),
    timeline: timeline,
    crew: stage ? crewFrom(stage.launch_crew) : [],
    spacecraft: stage && stage.spacecraft ? str(stage.spacecraft.name) : "",
    spacecraftType: stage && stage.spacecraft && stage.spacecraft.spacecraft_config ? str(stage.spacecraft.spacecraft_config.name) : "",
    destination: destination || (station ? (station.key === "iss" ? "International Space Station" : "Tiangong space station") : ""),
    station: station,
    missionDuration: stage ? formatDuration(stage.duration) : "",
    payloads: rocket.payloads ? rocket.payloads.length : 0,
    image: r.image ? str(r.image.thumbnail_url || r.image.image_url) : ""
  }
}

function parseLaunches(raw) {
  try {
    var data = JSON.parse(str(raw))
    var out = []
    for (var i = 0; i < (data.results || []).length; i++) out.push(parseLaunch(data.results[i]))
    out.sort(function(a, b) { return a.net - b.net })
    return out
  } catch (e) {
    return null
  }
}

function parseStations(raw) {
  try {
    var data = JSON.parse(str(raw))
    var out = {}
    var expeditions = {}
    for (var e = 0; e < (data.expeditions || []).length; e++) {
      var ex = data.expeditions[e]
      if (ex && ex.spacestation) {
        var list = expeditions[ex.spacestation.id] || []
        list.push({ name: str(ex.name), start: Date.parse(ex.start), crew: crewFrom(ex.crew) })
        expeditions[ex.spacestation.id] = list
      }
    }
    for (var i = 0; i < (data.stations || []).length; i++) {
      var s = data.stations[i]
      var meta = STATIONS[s.name]
      if (!meta) continue
      var exps = expeditions[s.id] || []
      var crew = []
      var names = []
      for (var x = 0; x < exps.length; x++) {
        names.push(exps[x].name)
        for (var c = 0; c < exps[x].crew.length; c++) crew.push(exps[x].crew[c])
      }
      out[meta.key] = {
        key: meta.key,
        name: str(s.name),
        short: meta.short,
        norad: meta.norad,
        founded: str(s.founded),
        description: str(s.description),
        onboardCrew: typeof s.onboard_crew === "number" ? s.onboard_crew : crew.length,
        dockedVehicles: typeof s.docked_vehicles === "number" ? s.docked_vehicles : 0,
        mass: s.mass,
        volume: s.volume,
        owners: (s.owners || []).map(function(o) { return str(o.abbrev || o.name) }).join(", "),
        expeditions: names.join(" · "),
        crew: crew
      }
    }
    return out
  } catch (err) {
    return null
  }
}

// CelesTrak GP JSON → mean elements keyed by NORAD id.
function parseTle(raw) {
  try {
    var data = JSON.parse(str(raw))
    var out = {}
    for (var i = 0; i < data.length; i++) {
      var g = data[i]
      out[g.NORAD_CAT_ID] = {
        name: str(g.OBJECT_NAME),
        epoch: Date.parse(str(g.EPOCH).replace(/(\.\d{3})\d*$/, "$1") + "Z"),
        meanMotion: g.MEAN_MOTION,          // rev/day
        meanMotionDot: g.MEAN_MOTION_DOT,   // rev/day² (already halved, TLE convention)
        inclination: g.INCLINATION,
        raan: g.RA_OF_ASC_NODE,
        argPerigee: g.ARG_OF_PERICENTER,
        meanAnomaly: g.MEAN_ANOMALY,
        eccentricity: g.ECCENTRICITY
      }
    }
    return out
  } catch (e) {
    return null
  }
}

// ---------------------------------------------------------------------------
// Orbital mechanics (simplified: circular orbits, J2 nodal regression).
// Plenty for a text-mode globe; not for anything that has to dock.

var MU = 398600.4418        // km³/s²
var RE = 6378.137           // km
var J2 = 1.08263e-3
var DEG = Math.PI / 180

function gmst(ms) {
  var jd = ms / 86400000 + 2440587.5
  var deg = 280.46061837 + 360.98564736629 * (jd - 2451545.0)
  return (((deg % 360) + 360) % 360) * DEG
}

function wrapLon(lon) { return ((lon + 540) % 360) - 180 }

function eciToGeo(x, y, z, ms) {
  var r = Math.sqrt(x * x + y * y + z * z)
  return {
    lat: Math.asin(z / r) / DEG,
    lon: wrapLon((Math.atan2(y, x) - gmst(ms)) / DEG)
  }
}

function orbitPoint(raan, inc, u) {
  var cO = Math.cos(raan), sO = Math.sin(raan), cI = Math.cos(inc), sI = Math.sin(inc)
  var cU = Math.cos(u), sU = Math.sin(u)
  return [cO * cU - sO * sU * cI, sO * cU + cO * sU * cI, sU * sI]
}

function nodalRate(n, a, inc) { return -1.5 * n * J2 * Math.pow(RE / a, 2) * Math.cos(inc) }

// Sub-satellite point of a station from its mean elements.
function stationPosition(el, ms) {
  var n = el.meanMotion * 2 * Math.PI / 86400
  var a = Math.pow(MU / (n * n), 1 / 3)
  var inc = el.inclination * DEG
  var dtSec = (ms - el.epoch) / 1000
  var dtDay = dtSec / 86400
  var raan = el.raan * DEG + nodalRate(n, a, inc) * dtSec
  var argp = el.argPerigee * DEG + 0.75 * n * J2 * Math.pow(RE / a, 2) * (5 * Math.cos(inc) * Math.cos(inc) - 1) * dtSec
  var revs = el.meanMotion * dtDay + el.meanMotionDot * dtDay * dtDay
  var u = argp + el.meanAnomaly * DEG + revs * 2 * Math.PI
  var p = orbitPoint(raan, inc, u)
  var g = eciToGeo(p[0], p[1], p[2], ms)
  g.alt = a - RE
  g.period = 1440 / el.meanMotion
  return g
}

function stationTrack(el, fromMs, toMs, stepSec) {
  var pts = []
  for (var t = fromMs; t <= toMs; t += stepSec * 1000) pts.push(stationPosition(el, t))
  return pts
}

// Best-guess target orbit for a launch. Returns { inc, alt, southbound, note }.
function targetOrbit(launch, tle) {
  var lat = Math.abs(launch.padLat)
  var abbrev = launch.orbitAbbrev
  var name = launch.name.toLowerCase()
  var o = { inc: Math.max(lat + 0.5, 45), alt: 400, southbound: false, estimated: true, note: "" }

  if (launch.station && tle && tle[launch.station.norad]) {
    var el = tle[launch.station.norad]
    o.inc = el.inclination
    o.alt = stationPosition(el, el.epoch).alt
    o.estimated = false
    o.note = "Rendezvous orbit matched to " + launch.station.short
  } else if (abbrev === "SSO") {
    o.inc = 97.6; o.alt = 550; o.southbound = true; o.note = "Sun-synchronous, ~97.6°"
  } else if (abbrev === "PO") {
    o.inc = 90; o.alt = 550; o.southbound = launch.padLat > 0 && launch.padLon < -100; o.note = "Polar, ~90°"
  } else if (abbrev === "GTO" || abbrev === "GEO" || abbrev === "GSO" || abbrev === "MEO" || abbrev === "HEO" ||
             abbrev === "TLI" || abbrev === "Lunar" || abbrev.indexOf("Helio") === 0 || abbrev === "L1" || abbrev === "L2" || abbrev === "Mars") {
    o.inc = lat + 0.5; o.alt = 200; o.note = "Parking orbit before departure burn (due east)"
  } else if (abbrev === "Sub") {
    o.inc = lat + 0.5; o.alt = 100; o.note = "Suborbital hop"; o.suborbital = true
  } else if (name.indexOf("starlink") >= 0) {
    o.inc = launch.padLon < -100 ? 53 : 43; o.alt = 280; o.note = "Starlink insertion shell"
    if (launch.padLon < -100 && name.indexOf("group 11") >= 0) o.inc = 53
  } else if (abbrev === "LEO") {
    o.note = "Generic low Earth orbit"
  } else {
    o.inc = lat + 0.5; o.note = "Orbit not published; due-east estimate"
  }
  // A pad can't reach an inclination below its own latitude.
  if (o.inc < lat + 0.1 && o.inc < 90) o.inc = lat + 0.1
  return o
}

// Ascent + orbit ground track from the pad. The ascent eases from 0 to orbital
// rate over the first ~8.5 minutes, which is roughly where most vehicles hit
// orbit. Returns { points:[{lat,lon,t}], insertion: index, orbit }.
var INSERTION_SEC = 510

function vehicleAngle(n, t) {
  if (t <= 0) return 0
  if (t < INSERTION_SEC) return n * t * t / (2 * INSERTION_SEC)
  return n * (INSERTION_SEC / 2 + (t - INSERTION_SEC))
}

function launchGeometry(launch, orbit) {
  var inc = orbit.inc * DEG
  var lat = launch.padLat * DEG
  var a = RE + orbit.alt
  var n = Math.sqrt(MU / (a * a * a))
  var s = Math.max(-1, Math.min(1, Math.sin(lat) / Math.sin(inc)))
  var u0 = orbit.southbound ? Math.PI - Math.asin(s) : Math.asin(s)
  // Pad in ECI at T-0, then solve for the node that puts it at u0.
  var padRa = launch.padLon * DEG + gmst(launch.net)
  var raan = padRa - Math.atan2(Math.cos(inc) * Math.sin(u0), Math.cos(u0))
  return { inc: inc, raan: raan, u0: u0, n: n, a: a, rate: nodalRate(n, a, inc) }
}

function vehiclePosition(launch, geo, tSec, suborbital) {
  var ms = launch.net + tSec * 1000
  if (tSec <= 0) return { lat: launch.padLat, lon: launch.padLon, t: tSec }
  var ang = vehicleAngle(geo.n, tSec) * (suborbital ? 0.06 : 1)
  var p = orbitPoint(geo.raan + geo.rate * tSec, geo.inc, geo.u0 + ang)
  var g = eciToGeo(p[0], p[1], p[2], ms)
  g.t = tSec
  return g
}

function launchTrack(launch, orbit, durationSec, stepSec) {
  var geo = launchGeometry(launch, orbit)
  var pts = []
  var insertion = 0
  var end = orbit.suborbital ? 600 : durationSec
  for (var t = 0; t <= end; t += stepSec) {
    pts.push(vehiclePosition(launch, geo, t, orbit.suborbital))
    if (t <= INSERTION_SEC) insertion = pts.length - 1
  }
  return { points: pts, insertion: insertion, geometry: geo, period: 2 * Math.PI / geo.n / 60 }
}

// Launch azimuth (degrees from north) at the pad, from the orbit geometry.
function launchAzimuth(launch, orbit) {
  var c = Math.cos(orbit.inc * DEG) / Math.cos(launch.padLat * DEG)
  var az = Math.asin(Math.max(-1, Math.min(1, c))) / DEG
  return orbit.southbound ? 180 - az : az
}

function compass(deg) {
  var names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
  return names[Math.round((((deg % 360) + 360) % 360) / 22.5) % 16]
}

function greatCircleKm(a, b) {
  var p1 = a.lat * DEG, p2 = b.lat * DEG, dl = (b.lon - a.lon) * DEG
  var h = Math.sin((p2 - p1) / 2) * Math.sin((p2 - p1) / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2)
  return 2 * RE * Math.asin(Math.min(1, Math.sqrt(h)))
}

function formatLatLon(p) {
  if (!p) return ""
  return Math.abs(p.lat).toFixed(1) + "°" + (p.lat >= 0 ? "N" : "S") + " " + Math.abs(p.lon).toFixed(1) + "°" + (p.lon >= 0 ? "E" : "W")
}

// ---------------------------------------------------------------------------
// Text globe

function subsolar(ms) {
  var d = new Date(ms)
  var start = Date.UTC(d.getUTCFullYear(), 0, 0)
  var doy = (ms - start) / 86400000
  var decl = 23.44 * Math.sin(2 * Math.PI * (doy - 81) / 365)
  var hours = d.getUTCHours() + d.getUTCMinutes() / 60
  return { lat: decl, lon: wrapLon(-15 * (hours - 12)) }
}

function esc(ch) {
  if (ch === " ") return "&nbsp;"
  if (ch === "<") return "&lt;"
  if (ch === ">") return "&gt;"
  if (ch === "&") return "&amp;"
  return ch
}

// opts: { cols, rows, lat, lon, zoom, mode: "globe"|"map", time,
//         colors: { land, landNight, ocean, oceanNight, grid },
//         layers: [{ points:[{lat,lon}], ch, color }],      // drawn in order
//         markers: [{ lat, lon, ch, color }] }               // drawn last
// Returns rich text (one <font> span per colour run).
function renderGlobe(opts) {
  var cols = opts.cols, rows = opts.rows
  var zoom = opts.zoom || 1
  var lat0 = opts.lat * DEG, lon0 = opts.lon
  var sinL0 = Math.sin(lat0), cosL0 = Math.cos(lat0)
  var globe = opts.mode !== "map"
  var colors = opts.colors
  var sun = subsolar(opts.time)
  var sunV = vec(sun.lat, sun.lon)

  // Character cells are about twice as tall as they are wide.
  var aspect = opts.aspect || 2.05
  var rx = (cols / 2 - 1) * zoom
  var ry = rx / aspect
  var cx = (cols - 1) / 2, cy = (rows - 1) / 2

  var grid = []
  for (var r = 0; r < rows; r++) {
    var line = []
    for (var c = 0; c < cols; c++) {
      var ll = globe ? unprojectOrtho((c - cx) / rx, (cy - r) / ry, sinL0, cosL0, lon0) : unprojectMap(c, r, cols, rows, opts.lat, lon0, zoom, aspect)
      if (!ll) { line.push({ ch: " ", color: "" }); continue }
      var v = vec(ll.lat, ll.lon)
      var day = v[0] * sunV[0] + v[1] * sunV[1] + v[2] * sunV[2] > -0.05
      var land = Land.isLand(ll.lat, ll.lon)
      var gridLine = (Math.abs(ll.lat) < 1.2 * (globe ? 1 : 0.5) / zoom) // equator
      var ch, color
      if (land) { ch = day ? "#" : "%"; color = day ? colors.land : colors.landNight }
      else if (gridLine) { ch = "-"; color = colors.grid }
      else { ch = day ? "." : " "; color = day ? colors.ocean : colors.oceanNight }
      if (globe && ll.edge && !land) { ch = "."; color = colors.grid }
      line.push({ ch: ch, color: color })
    }
    grid.push(line)
  }

  function plot(p, ch, color) {
    var cell = globe ? projectOrtho(p.lat, p.lon, sinL0, cosL0, lon0) : projectMap(p.lat, p.lon, cols, rows, opts.lat, lon0, zoom, aspect)
    if (!cell) return
    var c = Math.round(globe ? cx + cell.x * rx : cell.x)
    var r = Math.round(globe ? cy - cell.y * ry : cell.y)
    if (r < 0 || r >= rows || c < 0 || c >= cols) return
    grid[r][c] = { ch: ch, color: color }
  }

  for (var l = 0; l < (opts.layers || []).length; l++) {
    var layer = opts.layers[l]
    for (var i = 0; i < layer.points.length; i++) plot(layer.points[i], layer.ch, layer.color)
  }
  for (var m = 0; m < (opts.markers || []).length; m++) {
    var mk = opts.markers[m]
    if (mk) plot(mk, mk.ch, mk.color)
  }

  var html = []
  for (var y = 0; y < rows; y++) {
    var out = "", run = "", runColor = null
    for (var x = 0; x < cols; x++) {
      var cell = grid[y][x]
      if (cell.color !== runColor) {
        if (run) out += runColor ? "<font color=\"" + runColor + "\">" + run + "</font>" : run
        run = ""; runColor = cell.color
      }
      run += esc(cell.ch)
    }
    if (run) out += runColor ? "<font color=\"" + runColor + "\">" + run + "</font>" : run
    html.push(out)
  }
  return html.join("<br>")
}

function vec(lat, lon) {
  var p = lat * DEG, l = lon * DEG
  return [Math.cos(p) * Math.cos(l), Math.cos(p) * Math.sin(l), Math.sin(p)]
}

function unprojectOrtho(x, y, sinL0, cosL0, lon0) {
  var rho = Math.sqrt(x * x + y * y)
  if (rho > 1) return null
  if (rho < 1e-9) return { lat: Math.asin(sinL0) / DEG, lon: lon0 }
  var c = Math.asin(rho)
  var sc = Math.sin(c), cc = Math.cos(c)
  var lat = Math.asin(cc * sinL0 + y * sc * cosL0 / rho)
  var lon = lon0 + Math.atan2(x * sc, rho * cc * cosL0 - y * sc * sinL0) / DEG
  return { lat: lat / DEG, lon: wrapLon(lon), edge: rho > 0.97 }
}

function projectOrtho(lat, lon, sinL0, cosL0, lon0) {
  var p = lat * DEG, dl = (lon - lon0) * DEG
  var cosc = sinL0 * Math.sin(p) + cosL0 * Math.cos(p) * Math.cos(dl)
  if (cosc < 0) return null
  return { x: Math.cos(p) * Math.sin(dl), y: cosL0 * Math.sin(p) - sinL0 * Math.cos(p) * Math.cos(dl) }
}

function mapSpan(cols, rows, zoom, aspect) {
  // Equirectangular with square degrees: cells are `aspect` times taller than wide.
  var lonSpan = 360 / zoom
  var latSpan = lonSpan * (rows * (aspect || 2.05)) / cols
  return { lon: lonSpan, lat: Math.min(180, latSpan) }
}

function unprojectMap(c, r, cols, rows, lat0, lon0, zoom, aspect) {
  var span = mapSpan(cols, rows, zoom, aspect)
  var top = Math.min(90, Math.max(-90 + span.lat, lat0 + span.lat / 2))
  var lat = top - (r + 0.5) * span.lat / rows
  if (lat < -90 || lat > 90) return null
  return { lat: lat, lon: wrapLon(lon0 - span.lon / 2 + (c + 0.5) * span.lon / cols) }
}

function projectMap(lat, lon, cols, rows, lat0, lon0, zoom, aspect) {
  var span = mapSpan(cols, rows, zoom, aspect)
  var top = Math.min(90, Math.max(-90 + span.lat, lat0 + span.lat / 2))
  var dl = wrapLon(lon - lon0)
  return { x: (dl + span.lon / 2) / span.lon * cols - 0.5, y: (top - lat) / span.lat * rows - 0.5 }
}
