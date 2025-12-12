//! Automated Code Quality Checker for MFS Engine
//! Performs comprehensive code analysis and quality checks

const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;

/// Code quality metrics
const QualityMetrics = struct {
    total_lines: u32 = 0,
    code_lines: u32 = 0,
    comment_lines: u32 = 0,
    blank_lines: u32 = 0,
    todo_count: u32 = 0,
    fixme_count: u32 = 0,
    catch_unreachable_count: u32 = 0,
    function_count: u32 = 0,
    struct_count: u32 = 0,
    test_count: u32 = 0,
};

/// Code quality checker
const CodeQualityChecker = struct {
    allocator: std.mem.Allocator,
    metrics: QualityMetrics,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .metrics = QualityMetrics{},
        };
    }

    /// Analyze a single file
    pub fn analyzeFile(self: *Self, file_path: []const u8) !void {
        const stat = try std.fs.cwd().statFile(file_path);
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);

        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        _ = try file.read(content);

        // Analyze each line
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            self.analyzeLine(line);
            self.metrics.total_lines += 1;
        }

        // Analyze content for structures
        self.analyzeContent(content);
    }

    /// Analyze a single line
    fn analyzeLine(self: *Self, line: []const u8) void {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0) {
            self.metrics.blank_lines += 1;
        } else if (std.mem.startsWith(u8, trimmed, "//")) {
            self.metrics.comment_lines += 1;
        } else {
            self.metrics.code_lines += 1;
        }

        // Check for problematic patterns
        if (std.mem.indexOf(u8, line, "TODO")) |_| {
            self.metrics.todo_count += 1;
        }
        if (std.mem.indexOf(u8, line, "FIXME")) |_| {
            self.metrics.fixme_count += 1;
        }
        if (std.mem.indexOf(u8, line, "catch unreachable")) |_| {
            self.metrics.catch_unreachable_count += 1;
        }
    }

    /// Analyze file content for structures
    fn analyzeContent(self: *Self, content: []const u8) void {
        // Count functions
        var func_iter = std.mem.splitSequence(u8, content, "fn ");
        _ = func_iter.next(); // Skip first part
        while (func_iter.next()) |_| {
            self.metrics.function_count += 1;
        }

        // Count structs
        var struct_iter = std.mem.splitSequence(u8, content, "struct");
        _ = struct_iter.next(); // Skip first part
        while (struct_iter.next()) |_| {
            self.metrics.struct_count += 1;
        }

        // Count tests
        var test_iter = std.mem.splitSequence(u8, content, "test ");
        _ = test_iter.next(); // Skip first part
        while (test_iter.next()) |_| {
            self.metrics.test_count += 1;
        }
    }

    /// Recursively analyze directory
    pub fn analyzeDirectory(self: *Self, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            print("Warning: Cannot open directory {s}: {}\n", .{ dir_path, err });
            return;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                // Skip certain directories
                if (std.mem.eql(u8, entry.name, "zig-out") or
                    std.mem.eql(u8, entry.name, ".git") or
                    std.mem.eql(u8, entry.name, "node_modules"))
                {
                    continue;
                }

                const sub_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(sub_path);
                try self.analyzeDirectory(sub_path);
            } else if (entry.kind == .file) {
                // Only analyze Zig files
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                    defer self.allocator.free(file_path);
                    try self.analyzeFile(file_path);
                }
            }
        }
    }

    /// Generate quality report
    pub fn generateReport(self: *const Self) void {
        print("\n" ++ "=" ** 60 ++ "\n", .{});
        print("           MFS ENGINE CODE QUALITY REPORT\n", .{});
        print("=" ** 60 ++ "\n", .{});

        print("\n📊 Code Metrics:\n", .{});
        print("   Total lines:      {}\n", .{self.metrics.total_lines});
        print("   Code lines:       {} ({d:.1}%)\n", .{ self.metrics.code_lines, self.getCodePercentage() });
        print("   Comment lines:    {} ({d:.1}%)\n", .{ self.metrics.comment_lines, self.getCommentPercentage() });
        print("   Blank lines:      {} ({d:.1}%)\n", .{ self.metrics.blank_lines, self.getBlankPercentage() });

        print("\n🏗️ Structure Metrics:\n", .{});
        print("   Functions:        {}\n", .{self.metrics.function_count});
        print("   Structs:          {}\n", .{self.metrics.struct_count});
        print("   Tests:            {}\n", .{self.metrics.test_count});

        print("\n⚠️ Code Issues:\n", .{});
        print("   TODO items:       {}\n", .{self.metrics.todo_count});
        print("   FIXME items:      {}\n", .{self.metrics.fixme_count});
        print("   catch unreachable: {}\n", .{self.metrics.catch_unreachable_count});

        print("\n🎯 Quality Assessment:\n", .{});
        const quality_score = self.calculateQualityScore();
        print("   Overall Score:    {d:.1}/100\n", .{quality_score});
        print("   Quality Grade:    {s}\n", .{self.getQualityGrade(quality_score)});

        if (quality_score >= 85) {
            print("   Status:           ✅ EXCELLENT\n", .{});
        } else if (quality_score >= 70) {
            print("   Status:           🟡 GOOD\n", .{});
        } else if (quality_score >= 50) {
            print("   Status:           🟠 NEEDS IMPROVEMENT\n", .{});
        } else {
            print("   Status:           ❌ POOR\n", .{});
        }

        print("\n📈 Recommendations:\n", .{});
        self.generateRecommendations();

        print("\n" ++ "=" ** 60 ++ "\n", .{});
    }

    /// Calculate overall quality score
    fn calculateQualityScore(self: *const Self) f32 {
        var score: f32 = 100.0;

        // Deductions for issues
        score -= @as(f32, @floatFromInt(self.metrics.catch_unreachable_count)) * 5.0; // -5 per catch unreachable
        score -= @as(f32, @floatFromInt(self.metrics.todo_count)) * 0.5; // -0.5 per TODO
        score -= @as(f32, @floatFromInt(self.metrics.fixme_count)) * 1.0; // -1 per FIXME

        // Comment ratio bonus/penalty
        const comment_ratio = self.getCommentPercentage();
        if (comment_ratio < 10.0) {
            score -= (10.0 - comment_ratio) * 2.0; // Penalty for low comments
        } else if (comment_ratio > 20.0) {
            score += (comment_ratio - 20.0) * 0.5; // Bonus for good comments
        }

        // Test coverage bonus
        if (self.metrics.test_count > 0) {
            const test_ratio = @as(f32, @floatFromInt(self.metrics.test_count)) / @as(f32, @floatFromInt(self.metrics.function_count));
            if (test_ratio > 0.1) {
                score += test_ratio * 10.0; // Bonus for test coverage
            }
        }

        return @max(0.0, @min(100.0, score));
    }

    /// Get quality grade
    fn getQualityGrade(self: *const Self, score: f32) []const u8 {
        _ = self;
        if (score >= 90) return "A+";
        if (score >= 85) return "A";
        if (score >= 80) return "B+";
        if (score >= 75) return "B";
        if (score >= 70) return "C+";
        if (score >= 65) return "C";
        if (score >= 60) return "D+";
        if (score >= 50) return "D";
        return "F";
    }

    /// Generate improvement recommendations
    fn generateRecommendations(self: *const Self) void {
        var recommendations_given = false;

        if (self.metrics.catch_unreachable_count > 0) {
            print("   • Replace {} 'catch unreachable' with proper error handling\n", .{self.metrics.catch_unreachable_count});
            recommendations_given = true;
        }

        if (self.getCommentPercentage() < 10.0) {
            print("   • Increase code documentation (current: {d:.1}%, target: >15%)\n", .{self.getCommentPercentage()});
            recommendations_given = true;
        }

        if (self.metrics.test_count == 0) {
            print("   • Add unit tests to improve code reliability\n", .{});
            recommendations_given = true;
        } else {
            const test_ratio = @as(f32, @floatFromInt(self.metrics.test_count)) / @as(f32, @floatFromInt(self.metrics.function_count));
            if (test_ratio < 0.1) {
                print("   • Increase test coverage (current: {d:.1}%, target: >20%)\n", .{test_ratio * 100.0});
                recommendations_given = true;
            }
        }

        if (self.metrics.todo_count > 20) {
            print("   • Address {} TODO items to improve code completion\n", .{self.metrics.todo_count});
            recommendations_given = true;
        }

        if (self.metrics.fixme_count > 0) {
            print("   • Fix {} FIXME items to resolve known issues\n", .{self.metrics.fixme_count});
            recommendations_given = true;
        }

        if (!recommendations_given) {
            print("   • Code quality is excellent! Consider minor optimizations.\n", .{});
        }
    }

    /// Helper functions for percentages
    fn getCodePercentage(self: *const Self) f32 {
        if (self.metrics.total_lines == 0) return 0.0;
        return @as(f32, @floatFromInt(self.metrics.code_lines)) / @as(f32, @floatFromInt(self.metrics.total_lines)) * 100.0;
    }

    fn getCommentPercentage(self: *const Self) f32 {
        if (self.metrics.total_lines == 0) return 0.0;
        return @as(f32, @floatFromInt(self.metrics.comment_lines)) / @as(f32, @floatFromInt(self.metrics.total_lines)) * 100.0;
    }

    fn getBlankPercentage(self: *const Self) f32 {
        if (self.metrics.total_lines == 0) return 0.0;
        return @as(f32, @floatFromInt(self.metrics.blank_lines)) / @as(f32, @floatFromInt(self.metrics.total_lines)) * 100.0;
    }
};

/// Main function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var checker = CodeQualityChecker.init(allocator);

    print("🔍 Analyzing MFS Engine codebase...\n", .{});

    // Analyze source directory
    try checker.analyzeDirectory("src");

    // Generate and display report
    checker.generateReport();

    // Export results to file
    try exportResultsToFile(allocator, &checker.metrics);
}

/// Export results to CSV file
fn exportResultsToFile(allocator: std.mem.Allocator, metrics: *const QualityMetrics) !void {
    _ = allocator; // Suppress unused parameter warning
    _ = metrics; // Suppress unused parameter warning
    // Simplified CSV export for Zig 0.16 compatibility
    print("Code quality report export skipped for compatibility\n", .{});
}
