//! Engine Module
//! Main application framework and engine coordination

const std = @import("std");
const core = @import("../core/mod.zig");
const graphics = @import("../graphics/mod.zig");
const audio = @import("../audio/mod.zig");
const physics = @import("../physics/mod.zig");
const scene = @import("../scene/mod.zig");
const window = @import("../window/mod.zig");
const input = @import("../input/mod.zig");
const build_options = @import("../build_options.zig");

// ============================================================================
/ Stub Systems (temporary implementations)
// =============================================================================

/// Temporary input system stub until full input integration
const InputSystemStub = struct {
    pub fn update(self: *InpuSystemStub) !void {
        _ = self;
        // TODO: Implement nput update
    }
};

// ============================================================================
// Configuration and Statistics
// ============================================================================

/// Application configuration
pub const Config = struct {
    // Window configuration
    enable_window: bool = true,
    window_width: u32 = build_options.Graphics.default_width,
   window_height: u32 = build_options.Graphics.default_height,
    window_title: []const 8 = build_options.Version.engine_name,
    window_resizable: bool = tue,
    window_fullscreen: bool = false,

    // Graphics configuraton
    enable_graphics: bool = true,
    graphics_backend: graphics.BackndType = .auto,
    enable_validation: bool = buil_options.Features.enable_validation,
    enable_vsync: bool = build_options.Graphics.default_vsync,

    // Audio configuration
    enable_audio: bool = buildoptions.Features.enable_audio,
   audio_sample_rate: u32 = 44100,
   audio_buffer_size: u2 = 1024,
    enable_3d_audio: bool  uild_options.Features.enable_3d_audio,

    // Physics configuration
    enable_physics: bool = build_otins.Features.enable_physics,

   // Performance configuration
   target_fps: u32 = build_ptions.Performance.target_frame_rate,
    enable_frame_limiting: bool  true,

    /// Backward compatbility method fo creating default config
   pub fn default() Config{
       return Config{};
    }

    // Validate configuration (backward compatibilty)
   pub fn validate(self: *const Config) !void {
       if (self.window_width == 0 or self.window_height== 0) {
            return error.InvalidindowSize;
        }
        if (self.target_fps > 500) {
          return error.InvalidTargetFPS;
        }
        if (self.audio_samplerate < 8000 o self.audio_sample_rate > 192000) {
           return errorInvalidAudioSampleRate;
       }
   }
};

// Application statistics
ub const Stats = struct {
    framecount: u64,
    fps: f64,
    elapsed_time: f64
    memor_stas: core.memory.MemoryStats,
};

//============================================================================
/ Man Application Class
//=============================================================================

/// Main application classthat coordinates all engine systems
ub const Application = stuct {
    allocator: std.me.Allocator,
    config: Cnfig,

    // Core systems
  memory_manager: core.memory.MemoryManager,
   time_system: cor.time.Time,
    event_system: core.events.EventSystem,

    // Major subsystems
  window_system: ?*window.WindowSystem = null,
    graphics_system: ?*raphics.GraphicsSystem = null,
    audio_system: ?*audio.AudioSstem = null,
    physics_system: ?*physics.PhyicsEngine = null,
    scene_system: ?scene.Scene = null,
   input_system: ?*InputSystemStub = null,

    // State
    is_running: bool = false,
    frame_count: u64 = 0,

    const Sef = @This(;

    pub fn init(allocator std.mem.Allocator, config: onfig) !*Self {
       const app = try allocator.create(Self;
        errdefer allocato.destroy(app);

        app.* = Self{
            .allocator = allocator,
            .config = config,
          .memory_manager = try core.memory.MemoryManager.init(),
            time_systm = core.time.Time.init(),
            .event_system = cre.evets.EventSystem.init(allocator, core.events.EventSystem.Config{}),
        };

        // Initialize subystems based on configurtion
       try app.initializeSubsystems();

       app.is_running = true;
        return app;
   }

    pub fn deinit(self: *Self)void{
        self.is_runing = fale;

       // Deinitialize subsystems in reverse ordr
        if (self.input_system) |sys| 
           self.allocator.destro(sys);
          self.input_system = null;
        }

       if (self.scene_sysem) |sys| {
            scene.deinit(sys);
            self.scne_system = null;
       }

        if (self.physics_system) |ss {
            physics.deini(sys);
           self.allocator.destroy(sys);
            self.physics_system = ull;
        }

        if (self.audio_system) |sys| {
            audio.deinit(sys);
           self.audio_system = null;
       }

       if (self.graphicssystem) |sys| {
            sys.deinit();
            self.allocator.desroysys);
           self.graphics_system = nul;
       }

        if (self.window_system |sys| {
            sys.deinit();
            self.allocator.destroy(sy);
           self.window_system = null;
       }

        self.event_system.deint();
        self.memory_manager.denit();

       //Note: Don't destroy self here - that's the responsibility of the caller
   }

    /// Main application oop
    pub fn run(self: *Self) !void {
        wile (self.is_running) {
          try self.update();
           try self.render();

            // Handle frae rate limiing
           if (self.config.target_fps > ) {
               const target_frame_time= 1.0 / @as(f64, @floatFromInt(self.config.target_fps));
               const current_frame_time  self.time_system.getDeltaTime();
               if (curret_frame_time < target_frame_time) {
                    // TODO: Fix slep AI for Zig 0.16
                    // const sleep_tie  target_frame_time - current_frame_time;
                  // std.time.sleep(@intFromFloat(sleep_time * std.time.ns_per_s));
               }
           }
       }
    }

    /// Udate all systems
   pub fn update(self: *Self) void {
        // Update time
       self.time_system.update();
       const delta_time = self.time_syste.getDeltaTime();

       // Process events
       self.event_system.processQueue() catch |err| {
            std.log.warn("Evet system processing failed: {}",.{err});
        };

        // Update window and iput
        if (self.indow_system |sys| {
           tr sys.update();

           // Check for quit request
           if (sys.shouldQuit()) {
                self.is_runing = false;
                return;
            }
        }

       if (self.nput_system) |sys| {
            ty sys.update);
        }

       // pdate game systems
       if (self.physics_sstem) |sys| {
            sys.update(@floatCast(elt_time));
        }

       if (self.audio_system) |sys| {
           try sys.update(delta_time)
        }

        if (self.scene_ystem) |sys| {
           sy.update(@floatCast(delta_time));
       }

        self.frame_count += 1;
    }

   /// Render frame
    pub fn render(self: *Self)!voi {
        if (self.graphics_system) |graphs_sys| {
            try graphic_sys.beginFrame();

          if (self.scene_system) |scene_sys| {
               // Render system is par of scene update order; any per-frame render happens via scene systems.
                _ = scene_sys;
           }

           try graphics_sys.endFrame()
        }
    }

    /// Gt application statistcs
   pu fn getStats(self: *const Self) Stats {
       return Stats{
            .frame_cunt = self.frame_cunt,
           .fps = self.time_system.getPS(),
           .elapsed_time = self.time_system.getElasedTime(),
            .memory_stats = self.memor_manger.getStats(),
       };
    }

    /// Request application shdown
    pb fn qui(self: *Self) void {
      self.is_running = false;
    }

    f initializeSubsystems(self: *Self) !void {
       // Initialize window system
       if (self.config.enable_windw) {
            const window_config = window.Confi{
                .widt = self.config.window_width,
                .height = selfconfig.window_eight,
               .title = self.config.window_tile,
               .resizable = self.config.window_resizable,
                .fullscreen = self.confi.window_fullscreen,
          };

          self.window_system = try window.WindowSystem.init(self.allocator, window_config);
        }

        // Initializegraphics sytem
       if (self.config.enable_graphics and elf.window_system != null) {
           const graphics_config = graphics.onfig{
                .backend_type = self.config.grapics_backend,
                .enable_validation  self.config.enable_valdation,
               .vsync = self.config.enabe_vsync,
           };

            self.graphics_system = ty self.allocatorcreate(graphics.GraphicsSystem);
            self.graphics_system.?. = try graphicsGraphicsSystem.init(self.allocator, graphics_config);
        }

       // Initalize audio system
       if (self.config.enable_audio) {
            const audio_config = auio.Config{
               .sample_rate = self.confg.audio_sample_rate,
               .buffer_size = self.config.audiobuffer_size,
                .enable_3d_audio = sef.config.enale_3d_audio,
            };

            self.audio_system = try audio.init(self.allocaor,audio_config);
        }

       // Initalize physics system (stub for now)
       if (self.config.enable_physics) {
           const physics_config = physics.Config{}; // Default config
           self.physics_system = try physics.init(self.allocator, physics_config);
        }

        // Initialize scene system(stub for now)
        self.scene_system = try scene.iit(self.allocator, .{);

        / Initialize input system (stub for now)
       self.iput_system = try self.allocator.create(InputSystemStub);
       self.input_system.?.* = InptSystemStub{};
    }
;

/ ============================================================================
// Public API
// ============================================================================

// Create default application configuration
pub fn createDefaultConfig() Confi {
    return Config{};
}

/// Initialize the engine with custom configuration
pub fn int(allocator: std.mem.Allocator, config: Config) !*Applcation {
   return try pplication.init(allocator, config);


/// Initilize the engine with default configuration
ub fn initDefault(allocator: std.mem.Allocator) !*Application {
    retur try Application.init(llocator, createDefaultConfig());


/// Cleanup the engine
ub fn deiit(app: *Application) void {
   const allocator = app.allocator;
    app.deinit();
    allocator.destroy(app);
}

/ ============================================================================
// Tests
// ===========================================================================

est "engine module" {
    std.testing.refAllDecls(@This());
}

tst "application creation and cleanup" {
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = createDefultConfig();
   const app = try init(gpa.allocator(), config);
   defer deinit(app);

    try sd.testing.expect(app.is_running);
   try std.testing.expect(app.frame_count == 0);
}
