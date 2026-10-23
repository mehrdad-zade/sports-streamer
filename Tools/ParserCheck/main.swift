// Parser smoke test on macOS:
//   swiftc -o /tmp/pc Tools/ParserCheck/main.swift SportsStreamer/Scraping/{HTML,EventListParser,SourceParser}.swift SportsStreamer/Models/*.swift
//   /tmp/pc home.html https://site/ event.html https://site/events/x
import Foundation

let args = CommandLine.arguments
guard args.count >= 5 else { fatalError("usage: pc home.html homeURL event.html eventURL") }

let home = try String(contentsOfFile: args[1], encoding: .utf8)
let events = EventListParser.parse(html: home, pageURL: URL(string: args[2])!)
print("EVENTS (\(events.count))")
for e in events { print(" ", e.isLive ? "LIVE" : "    ", e.title, "|", e.subtitle ?? "", "|", e.teams, "|", e.url.path) }
print("CATEGORIES", EventListParser.categoryLinks(html: home, pageURL: URL(string: args[2])!).map { "\($0.name)=\($0.url.path)" })
print("SEARCH 'dortmund':", events.filter { $0.matches("dortmund") }.map(\.title))

let page = try String(contentsOfFile: args[3], encoding: .utf8)
let sources = SourceParser.parse(html: page, pageURL: URL(string: args[4])!)
print("SOURCES (\(sources.count))")
for s in sources { print("  #\(s.id)", s.label, "|", s.embedURL.absoluteString, "| wrapper:", s.pageURL.host ?? "") }
