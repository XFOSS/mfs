# MFS Engine – Completion Plan 2024

> **Purpose**  
> This document consolidates every outstanding TODO, missing subsystem, and quality-of-life improvement required to take the MFS Engine from its current 🚧 *work-in-progress* state to the **feature-complete, production-ready** milestone (v1.0 GA).  It is intended to replace scattered notes, TODO comments, and partial roadmaps with a single authoritative plan.

---

## 0. Executive Summary

The engine already boasts a robust core, but critical gaps remain in **Graphics**, **Physics**, **Audio**, **Scene Systems**, and **Tooling**.  The strategy below attacks the remaining work in five highly-parallel tracks so the team can deliver a *Developer Preview* in **Q2 2024** and a **v1.0 GA** in **Q3 2024**.

| Track | Goal | Key Owners | ETA |
|-------|------|------------|-----|
| 1️⃣ Graphics | Ship unified backend abstraction + Vulkan & OpenGL parity | @gfx-team | **May 2024** |
| 2️⃣ Physics  | Complete constraints, collision, multithreaded solver    | @physics-team | **Jun 2024** |
| 3️⃣ Engine Core | ECS optimisation + resource hot-reload + deterministic main-loop | @core-team | **May 2024** |
| 4️⃣ Audio/UI | Finalise OpenAL glue + modern UI renderer                   | @systems-team | **Jun 2024** |
| 5️⃣ Tooling  | CLI asset-pipeline, profiler, editor MVP                   | @tools-team | **Jul 2024** |

---

## 1. High-Priority TODO Matrix

Below is the distilled list of the **102** highest-impact TODOs extracted from the source tree (see *scripts/todo_report.json* for the machine-generated full list). Each is mapped to a track and given a realistic complexity estimate.

| ID | File | Line | Description | Track | Complexity |
|----|------|------|-------------|-------|------------|
| G-01 | `src/graphics/render/mod.zig` | 35 | Implement clear functionality | Graphics | S |
| G-02 | … | … | Implement triangle drawing | Graphics | S |
| G-15 | `src/graphics/backends/opengl_backend.zig` | 543 | Texture destruction | Graphics | M |
| P-03 | `src/physics/physics_engine.zig` | 281 | Other constraint types | Physics | L |
| … | … | … | … | … | … |

> **S** = <4 hrs, **M** = 1-2 days, **L** = >2 days.

---

## 2. Milestone Breakdown

### Milestone M2 – *Graphics Excellence* (**ETA 2024-05-31**)
1. Backend Manager refactor (`src/graphics/backend_manager.zig`)
2. Vulkan render-pass & swap-chain recreation (#47, #52)
3. OpenGL pipeline binding & resource destruction (G-15, G-18)
4. Shader Manager link-time reflection (G-23)

**Exit Criteria**: `zig build run-vulkan-cube` renders at 60 FPS on Linux & Windows. All graphics tests pass on CI.

### Milestone M3 – *Physics & Core* (**ETA 2024-06-30**)
1. Finish constraint system (P-03–P-09)
2. Integrate broad-phase BVH optimisation (#88)
3. Main loop deterministic fixed-step refactor (#105)

**Exit Criteria**: Physics demo stable for 10k bodies; frame-time variance <1 ms.

### Milestone M4 – *Developer Experience* (**ETA 2024-07-31**)
1. Asset pipeline CLI (T-04)
2. Profiler overlay & standalone visualiser (T-09)
3. Visual Editor MVP with scene hierarchy & inspector (T-12)

---

## 3. Resourcing Plan

* 2 FTE senior graphics engineers → Track 1
* 1 FTE physics specialist + 1 junior → Track 2
* 2 generalists → Track 3
* 1 audio/UX engineer → Track 4
* 1 tools engineer + 1 UX designer → Track 5

---

## 4. Risk Register & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Vulkan spec churn | M | H | Pin to 1.3 header; CI against latest drivers |
| Scope creep in editor | H | M | Freeze feature list post-M4; follow RFC process |
| Multiplatform window handling | M | M | Abstract through `platform/window` module, expand CI matrix |

---

## 5. Next Steps (Sprint 0 – Kick-off)

1. ✅ Approve this plan (stakeholder sign-off)
2. ✅ Create linear issue-board with IDs above
3. 🚧 Stand-up daily sync; weekly demo build
4. 🚧 Automate TODO extraction (`scripts/todo_report.zig`)

---

*Maintained by **@mfs-pm**.  Automatically closes on v1.0 GA tag.*