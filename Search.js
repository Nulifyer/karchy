// Pure path-aware subsequence ranking. No filesystem or shell access here.
function fuzzyScore(text, query) {
  text = text.toLowerCase()
  query = query.toLowerCase()
  if (!query) return 0
  var previous = []
  for (var i = 0; i < query.length; i++) {
    var current = []
    var bestGap = -Infinity
    for (var j = 0; j < text.length; j++) {
      if (i > 0 && j > 0) bestGap = Math.max(bestGap, previous[j - 1] + j)
      var score = -Infinity
      if (text[j] === query[i]) {
        var boundary = j === 0 || /[\/\s_.-]/.test(text[j - 1])
        var bonus = 10 + (boundary ? 12 : 0)
        if (i === 0) score = bonus - j * 0.2
        else score = Math.max(bestGap - j + bonus, j > 0 ? previous[j - 1] + bonus + 16 : -Infinity)
      }
      current.push(score)
    }
    previous = current
  }
  return previous.length ? Math.max.apply(null, previous) : -Infinity
}

function rank(projects, query) {
  var tokens = query.toLowerCase().trim().split(/\s+/).filter(function(s) { return s.length > 0 })
  var matches = []
  for (var i = 0; i < projects.length; i++) {
    var row = projects[i]
    var score = 0
    for (var t = 0; t < tokens.length; t++) {
      var token = tokens[t]
      var nameScore = fuzzyScore(row.name, token)
      var pathScore = fuzzyScore(row.path, token)
      var part = Math.max(isFinite(nameScore) ? nameScore + 35 : -Infinity, pathScore)
      if (!isFinite(part)) { score = -Infinity; break }
      if (row.name.toLowerCase() === token) part += 120
      else if (row.name.toLowerCase().indexOf(token) === 0) part += 45
      score += part
    }
    if (isFinite(score)) matches.push({ row: row, score: score, order: i })
  }
  matches.sort(function(a, b) {
    return b.score - a.score || Number(b.row.primary) - Number(a.row.primary) || a.order - b.order
  })
  return matches.map(function(match) { return match.row })
}

function plainLabel(value) {
  return String(value).replace(/[\t\r\n]/g, " ")
}
