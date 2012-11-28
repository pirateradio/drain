coffee   = require("coffee-script")
express  = require("express")
librato  = require("librato-metrics").createClient(email:process.env.LIBRATO_EMAIL, token:process.env.LIBRATO_TOKEN)
log      = require("./lib/logger").init("drain")

express.logger.format "method", (req, res) ->
  req.method.toLowerCase()

express.logger.format "url", (req, res) ->
  req.url.replace('"', '&quot')

express.logger.format "user-agent", (req, res) ->
  (req.headers["user-agent"] || "").replace('"', '')

every = (ms, cb) -> setInterval cb, ms

app = express.createServer(
  express.logger
    buffer: false
    format: "ns=\"drain\" measure=\"http.:method\" source=\":url\" status=\":status\" elapsed=\":response-time\" from=\":remote-addr\" agent=\":user-agent\""
  express.logger()
  express.bodyParser())

app.get "/", (req, res) ->
  res.send "ok"

app.post "/logs", (req, res) ->
  measurements = {}
  units = {}
  has_values = {}
  log.start "logs", (logger) ->
    try
      for entry in JSON.parse(req.body.payload).events
        if pairs = entry.message.match(/([a-zA-Z0-9\_\-\.]+)=?(([a-zA-Z0-9\.\-\_\.]+)|("([^\"]+)"))?/g)
          attrs = {}
          for pair in pairs
            parts = pair.split("=")
            key   = parts.shift()
            value = parts.join("=")
            value = value.substring(1, value.length-1) if value[0] is '"'
            attrs[key] = value
          if attrs.measure
            name = attrs.measure
            name = "#{attrs.ns}.#{name}" if attrs.ns
            source = attrs.source || ""
            value = attrs.value || attrs.val
            measurements[name] ||= {}
            measurements[name][source] ||= []
            measurements[name][source].push(parseInt(value || "1"))
            units[name] ||= attrs.units
            has_values[name] = true if value
      gauges = []
      for name, source_values of measurements
        for source, values of source_values
          sorted = values.sort()
          sum    = sorted.reduce (ax, n) -> ax+n
          if has_values[name]
            gauges.push create_gauge("#{name}.mean",   source, (sum / sorted.length).toFixed(3),        units[name], "average")
            gauges.push create_gauge("#{name}.perc95", source, sorted[Math.ceil(0.95*sorted.length)-1], units[name], "average")
            gauges.push create_gauge("#{name}.count",  source, sorted.length,                           "count",     "sum")
          else
            gauges.push create_gauge("#{name}.count", source, sorted.length, "count", "sum")
      librato.post "/metrics", gauges:gauges, (err, result) ->
        if err
          logger.error err
          res.send "error", 422
        else
          logger.success()
          for gauge in gauges
            log.success metric:gauge.name, value:gauge.value, source:gauge.source
          res.send "ok"
    catch err
      logger.error err
      res.send "error", 422

create_gauge = (name, source, value, units, summarization) ->
  gauge =
    name:   name
    value:  value.toString()
    attributes:
      display_min: 0
      display_units_long:  (units || "count")
      summarize_function: (summarization || "average")
  gauge.source = source.replace(/\//g, ":") unless source is ""
  gauge

module.exports = app
