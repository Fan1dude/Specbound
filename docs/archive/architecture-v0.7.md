> **Archived 2026-07-28 — superseded by `../ARCHITECTURE.md` and `../PRODUCT_ARCHITECTURE.md`. Historical reference only; do not treat as current.**

# Specbound Architecture

Version: 0.7 (Project Blueprint)

---

# Mission

Specbound exists to help builders document their work from the first idea to the finished product.

Instead of only sharing the final result, builders can share the entire journey.

---

# Core Philosophy

Every build has a story.

Every revision teaches something.

Every builder can inspire someone else.

---

# Primary Objects

Builder

↓

Build

↓

Revision

↓

Setup

↓

Collection

↓

Component

---

# Builder

A Builder is a person using Specbound.

Fields

- Username
- Display Name
- Bio
- Avatar
- Banner
- Joined Date
- Social Links

Relationships

Builder

├── Builds

├── Setups

├── Collections

└── Followers

---

# Build

A Build represents something someone created.

Examples

- Gaming PC
- Arduino Robot
- Mechanical Keyboard
- 3D Printed Helmet
- Raspberry Pi NAS

Fields

- Title
- Description
- Category
- Difficulty
- Cost
- Status
- Images
- Specifications
- Creator

A Build contains Revisions.

---

# Revision

This is Specbound's signature feature.

Every Build has a timeline of revisions.

Each Revision stores

- Version
- Date
- Images
- Notes
- Changes
- Lessons Learned

Example

Prototype

↓

Revision 1

↓

Revision 2

↓

Finished Build

---

# Setup

A Setup represents a complete workspace.

Examples

- Gaming Desk
- Streaming Setup
- Electronics Bench
- Study Workspace

A Setup links together multiple Builds.

Example

Gaming Setup

├── Gaming PC

├── Keyboard

├── Mouse

├── Speakers

├── Lighting

└── Desk

---

# Collection

A Collection groups similar Builds.

Examples

Arduino Starter Projects

Water Cooling Builds

White PC Builds

Retro Consoles

Collections can be public.

---

# Components

Components are reusable parts.

Examples

CPU

GPU

SSD

Motherboard

Arduino Uno

Servo

Stepper Motor

A Component may appear in many Builds.

---

# Categories

Categories are NOT hardcoded.

They should eventually live in the database.

Examples

PC Builds

Arduino

Robotics

Setups

Electronics

Mechanical Keyboards

3D Printing

Networking

Servers

DIY

---

# Design Principles

Document.

Improve.

Share.

Inspire.

---

# UI Principles

Dark workspace.

Blueprint visuals.

Minimal interface.

Large typography.

One accent color.

Consistent spacing.

---

# Future Features

Builder Reputation

Achievements

Revision Timeline

Component Database

Collections

Following Builders

Bookmarks

Notifications

API

Mobile App

---

# Guiding Principle

Everything should connect.

Builders create Builds.

Builds contain Revisions.

Setups organize Builds.

Collections organize knowledge.

Components connect Builds together.

The platform should feel like an engineering notebook rather than a social media feed.