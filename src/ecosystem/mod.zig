//! MFS Engine - Ecosystem Module
//! Community features, plugin system, and ecosystem management

pub const community = @import("community.zig");

// Re-export main types
pub const PluginSystem = community.PluginSystem;
pub const Plugin = community.Plugin;
pub const AssetStore = community.AssetStore;
pub const CommunityContributions = community.CommunityContributions;
pub const Documentation = community.Documentation;
pub const CommunityMetrics = community.CommunityMetrics;

// Re-export example plugins
pub const ExamplePlugins = community.ExamplePlugins;
