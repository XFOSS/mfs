const std = @import("std");

// Simple Markdown to HTML converter for MFS Engine documentation
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <input.md> <output.html> [title]\n", .{args[0]});
        return error.InvalidArguments;
    }

    const input_path = args[1];
    const output_path = args[2];
    const title = if (args.len >= 4) args[3] else "MFS Engine Documentation";

    // Read markdown file
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();
    const markdown_content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(markdown_content);

    // Convert markdown to HTML
    const html_content = try markdownToHtml(allocator, markdown_content, title);

    // Write HTML file
    try std.fs.cwd().writeFile(.{
        .sub_path = output_path,
        .data = html_content,
    });
}

fn markdownToHtml(allocator: std.mem.Allocator, markdown: []const u8, title: []const u8) ![]const u8 {
    var html = std.array_list.Managed(u8).init(allocator);
    defer html.deinit();

    // HTML template header
    const header = try std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>{s} - MFS Engine Documentation</title>
        \\    <style>
        \\        * {{
        \\            margin: 0;
        \\            padding: 0;
        \\            box-sizing: border-box;
        \\        }}
        \\
        \\        body {{
        \\            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        \\            line-height: 1.6;
        \\            color: #333;
        \\            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        \\            min-height: 100vh;
        \\        }}
        \\
        \\        .container {{
        \\            max-width: 1200px;
        \\            margin: 0 auto;
        \\            padding: 2rem;
        \\        }}
        \\
        \\        header {{
        \\            text-align: center;
        \\            margin-bottom: 3rem;
        \\            color: white;
        \\        }}
        \\
        \\        .logo {{
        \\            font-size: 3rem;
        \\            font-weight: bold;
        \\            margin-bottom: 0.5rem;
        \\            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        \\        }}
        \\
        \\        .tagline {{
        \\            font-size: 1.2rem;
        \\            opacity: 0.9;
        \\            margin-bottom: 1rem;
        \\        }}
        \\
        \\        .badges {{
        \\            display: flex;
        \\            justify-content: center;
        \\            gap: 0.5rem;
        \\            flex-wrap: wrap;
        \\            margin-bottom: 2rem;
        \\        }}
        \\
        \\        .badge {{
        \\            background: rgba(255,255,255,0.2);
        \\            padding: 0.3rem 0.8rem;
        \\            border-radius: 20px;
        \\            font-size: 0.9rem;
        \\            backdrop-filter: blur(10px);
        \\        }}
        \\
        \\        .content {{
        \\            background: white;
        \\            border-radius: 15px;
        \\            padding: 2rem;
        \\            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        \\        }}
        \\
        \\        .doc-content {{
        \\            max-width: none;
        \\        }}
        \\
        \\        h1 {{
        \\            color: #2d3748;
        \\            font-size: 2.5rem;
        \\            margin-bottom: 2rem;
        \\            text-align: center;
        \\            border-bottom: 3px solid #667eea;
        \\            padding-bottom: 1rem;
        \\        }}
        \\
        \\        h2 {{
        \\            color: #4a5568;
        \\            font-size: 2rem;
        \\            margin: 2rem 0 1rem 0;
        \\            border-bottom: 2px solid #e2e8f0;
        \\            padding-bottom: 0.5rem;
        \\        }}
        \\
        \\        h3 {{
        \\            color: #2d3748;
        \\            font-size: 1.5rem;
        \\            margin: 1.5rem 0 1rem 0;
        \\        }}
        \\
        \\        h4 {{
        \\            color: #4a5568;
        \\            font-size: 1.25rem;
        \\            margin: 1.25rem 0 0.75rem 0;
        \\        }}
        \\
        \\        p {{
        \\            margin-bottom: 1rem;
        \\            line-height: 1.7;
        \\        }}
        \\
        \\        pre {{
        \\            background: #f8fafc;
        \\            border: 1px solid #e2e8f0;
        \\            border-radius: 8px;
        \\            padding: 1rem;
        \\            margin: 1rem 0;
        \\            overflow-x: auto;
        \\            font-family: 'Monaco', 'Consolas', monospace;
        \\            font-size: 0.9rem;
        \\        }}
        \\
        \\        code {{
        \\            background: #f1f5f9;
        \\            padding: 0.2rem 0.4rem;
        \\            border-radius: 4px;
        \\            font-family: 'Monaco', 'Consolas', monospace;
        \\            font-size: 0.85rem;
        \\        }}
        \\
        \\        pre code {{
        \\            background: none;
        \\            padding: 0;
        \\        }}
        \\
        \\        ul, ol {{
        \\            margin: 1rem 0;
        \\            padding-left: 2rem;
        \\        }}
        \\
        \\        li {{
        \\            margin-bottom: 0.5rem;
        \\        }}
        \\
        \\        table {{
        \\            width: 100%;
        \\            border-collapse: collapse;
        \\            margin: 1rem 0;
        \\            background: white;
        \\        }}
        \\
        \\        th, td {{
        \\            border: 1px solid #e2e8f0;
        \\            padding: 0.75rem;
        \\            text-align: left;
        \\        }}
        \\
        \\        th {{
        \\            background: #f8fafc;
        \\            font-weight: 600;
        \\            color: #2d3748;
        \\        }}
        \\
        \\        tr:nth-child(even) {{
        \\            background: #f8fafc;
        \\        }}
        \\
        \\        blockquote {{
        \\            border-left: 4px solid #667eea;
        \\            padding-left: 1rem;
        \\            margin: 1.5rem 0;
        \\            color: #4a5568;
        \\            font-style: italic;
        \\        }}
        \\
        \\        a {{
        \\            color: #667eea;
        \\            text-decoration: none;
        \\        }}
        \\
        \\        a:hover {{
        \\            text-decoration: underline;
        \\        }}
        \\
        \\        .nav {{
        \\            margin-top: 2rem;
        \\            padding-top: 2rem;
        \\            border-top: 1px solid #e2e8f0;
        \\            text-align: center;
        \\        }}
        \\
        \\        .nav a {{
        \\            margin: 0 1rem;
        \\            color: #667eea;
        \\        }}
        \\
        \\        @media (max-width: 768px) {{
        \\            .container {{
        \\                padding: 1rem;
        \\            }}
        \\
        \\            h1 {{
        \\                font-size: 2rem;
        \\            }}
        \\
        \\            h2 {{
        \\                font-size: 1.5rem;
        \\            }}
        \\
        \\            table {{
        \\                font-size: 0.9rem;
        \\            }}
        \\        }}
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <header>
        \\            <div class="logo">🎮 MFS Engine</div>
        \\            <div class="tagline">Multi-Platform Game Engine Documentation</div>
        \\            <div class="badges">
        \\                <span class="badge">Production Ready</span>
        \\                <span class="badge">Zig 0.12.0</span>
        \\                <span class="badge">Cross-Platform</span>
        \\                <span class="badge">Ray Tracing</span>
        \\                <span class="badge">Open Source</span>
        \\            </div>
        \\        </header>
        \\
        \\        <div class="content">
        \\            <div class="doc-content">
    , .{title});
    defer allocator.free(header);

    try html.appendSlice(header);

    // Convert markdown to HTML
    try convertMarkdown(allocator, &html, markdown);

    // HTML template footer
    const footer =
        \\            </div>
        \\            <div class="nav">
        \\                <a href="index.html">← Back to Documentation Index</a>
        \\            </div>
        \\        </div>
        \\    </div>
        \\</body>
        \\</html>
        \\
    ;

    try html.appendSlice(footer);

    return html.toOwnedSlice();
}

fn convertMarkdown(allocator: std.mem.Allocator, html: *std.array_list.Managed(u8), markdown: []const u8) !void {
    var lines = std.mem.split(u8, markdown, "\n");
    var in_code_block = false;
    var code_language = "";

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "```")) {
            if (in_code_block) {
                // End code block
                try html.appendSlice("</code></pre>\n");
                in_code_block = false;
                code_language = "";
            } else {
                // Start code block
                in_code_block = true;
                if (trimmed.len > 3) {
                    code_language = trimmed[3..];
                }
                try html.appendSlice("<pre><code");
                if (code_language.len > 0) {
                    try html.appendSlice(" class=\"language-");
                    try html.appendSlice(code_language);
                    try html.appendSlice("\"");
                }
                try html.appendSlice(">");
            }
            continue;
        }

        if (in_code_block) {
            // Inside code block, just escape HTML entities
            const escaped = try escapeHtml(allocator, line);
            defer allocator.free(escaped);
            try html.appendSlice(escaped);
            try html.appendSlice("\n");
            continue;
        }

        if (trimmed.len == 0) {
            try html.appendSlice("<p></p>\n");
            continue;
        }

        // Headers
        if (std.mem.startsWith(u8, trimmed, "# ")) {
            const content = trimmed[2..];
            const escaped = try escapeHtml(allocator, content);
            defer allocator.free(escaped);
            try html.appendSlice("<h1>");
            try html.appendSlice(escaped);
            try html.appendSlice("</h1>\n");
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "## ")) {
            const content = trimmed[3..];
            const escaped = try escapeHtml(allocator, content);
            defer allocator.free(escaped);
            try html.appendSlice("<h2>");
            try html.appendSlice(escaped);
            try html.appendSlice("</h2>\n");
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "### ")) {
            const content = trimmed[4..];
            const escaped = try escapeHtml(allocator, content);
            defer allocator.free(escaped);
            try html.appendSlice("<h3>");
            try html.appendSlice(escaped);
            try html.appendSlice("</h3>\n");
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "#### ")) {
            const content = trimmed[5..];
            const escaped = try escapeHtml(allocator, content);
            defer allocator.free(escaped);
            try html.appendSlice("<h4>");
            try html.appendSlice(escaped);
            try html.appendSlice("</h4>\n");
            continue;
        }

        // Lists
        if (std.mem.startsWith(u8, trimmed, "- ") or std.mem.startsWith(u8, trimmed, "* ")) {
            const content = try convertInlineMarkdown(allocator, trimmed[2..]);
            defer allocator.free(content);
            try html.appendSlice("<ul><li>");
            try html.appendSlice(content);
            try html.appendSlice("</li></ul>\n");
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "1. ")) {
            const content = try convertInlineMarkdown(allocator, trimmed[3..]);
            defer allocator.free(content);
            try html.appendSlice("<ol><li>");
            try html.appendSlice(content);
            try html.appendSlice("</li></ol>\n");
            continue;
        }

        // Blockquotes
        if (std.mem.startsWith(u8, trimmed, "> ")) {
            const content = try convertInlineMarkdown(allocator, trimmed[2..]);
            defer allocator.free(content);
            try html.appendSlice("<blockquote><p>");
            try html.appendSlice(content);
            try html.appendSlice("</p></blockquote>\n");
            continue;
        }

        // Tables (basic support)
        if (std.mem.indexOf(u8, trimmed, "|") != null and !std.mem.startsWith(u8, trimmed, "|-")) {
            try convertTableRow(allocator, html, trimmed);
            continue;
        }

        // Regular paragraph
        const content = try convertInlineMarkdown(allocator, trimmed);
        defer allocator.free(content);
        try html.appendSlice("<p>");
        try html.appendSlice(content);
        try html.appendSlice("</p>\n");
    }
}

fn convertInlineMarkdown(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], "**") and std.mem.indexOf(u8, text[i + 2 ..], "**")) |end| {
            // Bold
            const content_start = i + 2;
            const content_end = i + 2 + end;
            try result.appendSlice("<strong>");
            const escaped = try escapeHtml(allocator, text[content_start..content_end]);
            defer allocator.free(escaped);
            try result.appendSlice(escaped);
            try result.appendSlice("</strong>");
            i = content_end + 2;
        } else if (std.mem.startsWith(u8, text[i..], "*") and std.mem.indexOf(u8, text[i + 1 ..], "*")) |end| {
            // Italic
            const content_start = i + 1;
            const content_end = i + 1 + end;
            try result.appendSlice("<em>");
            const escaped = try escapeHtml(allocator, text[content_start..content_end]);
            defer allocator.free(escaped);
            try result.appendSlice(escaped);
            try result.appendSlice("</em>");
            i = content_end + 1;
        } else if (std.mem.startsWith(u8, text[i..], "`") and std.mem.indexOf(u8, text[i + 1 ..], "`")) |end| {
            // Inline code
            const content_start = i + 1;
            const content_end = i + 1 + end;
            try result.appendSlice("<code>");
            const escaped = try escapeHtml(allocator, text[content_start..content_end]);
            defer allocator.free(escaped);
            try result.appendSlice(escaped);
            try result.appendSlice("</code>");
            i = content_end + 1;
        } else if (std.mem.startsWith(u8, text[i..], "[") and std.mem.indexOf(u8, text[i..], "](")) |link_text_end| {
            // Link
            const link_text = text[i + 1 .. i + link_text_end];
            const link_start = i + link_text_end + 2;
            if (std.mem.indexOf(u8, text[link_start..], ")")) |link_end| {
                const link_url = text[link_start .. link_start + link_end];
                try result.appendSlice("<a href=\"");
                try result.appendSlice(link_url);
                try result.appendSlice("\">");
                const escaped = try escapeHtml(allocator, link_text);
                defer allocator.free(escaped);
                try result.appendSlice(escaped);
                try result.appendSlice("</a>");
                i = link_start + link_end + 1;
            } else {
                // Not a valid link, just append the character
                try result.append(text[i]);
                i += 1;
            }
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

fn convertTableRow(allocator: std.mem.Allocator, html: *std.array_list.Managed(u8), row: []const u8) !void {
    var cells = std.array_list.Managed([]const u8).init(allocator);
    defer cells.deinit();

    var cell_start: usize = 0;
    var i: usize = 0;
    while (i < row.len) : (i += 1) {
        if (row[i] == '|') {
            const cell = std.mem.trim(u8, row[cell_start..i], " \t");
            try cells.append(cell);
            cell_start = i + 1;
        }
    }

    if (cells.items.len > 0) {
        try html.appendSlice("<table><tr>");
        for (cells.items) |cell| {
            const escaped = try escapeHtml(allocator, cell);
            defer allocator.free(escaped);
            try html.appendSlice("<td>");
            try html.appendSlice(escaped);
            try html.appendSlice("</td>");
        }
        try html.appendSlice("</tr></table>\n");
    }
}

fn escapeHtml(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    defer result.deinit();

    for (text) |char| {
        switch (char) {
            '&' => try result.appendSlice("&amp;"),
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#39;"),
            else => try result.append(char),
        }
    }

    return result.toOwnedSlice();
}
