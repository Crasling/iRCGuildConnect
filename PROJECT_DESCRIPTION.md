# iRC: Guild Connect

Formerly iRacelockConnection

iRC is a WoW Classic guild companion for any guild—from normal raiding, leveling, social, and community guilds to RaceLocked, Self-Found, and Guild Found challenge guilds.

It provides shared guild information, member presence and verification, guild statistics, onboarding tools, optional rule enforcement, economy controls, Guild Map positions, and officer tools.

Installing iRC does not automatically activate enforcement. The Guild Master chooses which features and rules the guild uses, so iRC can support a normal guild without imposing challenge restrictions. It can also remain installed safely on characters in unrelated guilds.

## For every guild

### Guild information and discovery

Guild Statistics provides an overview of participating guilds, including:

- Active level 60s during the last 30 days
- Active members during the last 30 days
- Highest known online count during the last 24 hours
- Total member count
- Race and class distribution
- Guild description, icon, and invite contacts
- Active guild rules, when configured
- Report source and last update

Normal, RaceLocked, and GuildFound filters make it easy to find the type of guild you want. Reports older than five days are automatically hidden. Recent reports can be shared between guild members to improve availability without publishing outdated local data.

### Normal raiding, social, and leveling guilds

A normal guild can use iRC without enabling Race Lock, Self-Found, Guild Found, or group restrictions.

Useful features for normal guilds include:

- Guild activity and roster statistics
- Class distribution and level breakdowns
- Custom Guild Homepage descriptions and icons
- Up to five invite contacts
- Member presence checks
- Welcome messages and onboarding
- Guild Map position sharing
- Delegated officer tools
- Guild-only group rules when desired

### Visible guild rules

Every member can see the rules currently configured for their guild. All challenge and enforcement rules are optional.

Available rules include:

- Race Lock
- Native racial language
- Self-Found only
- Guild Found
- Self-Found or Guild Found progression
- Guild Found at level 60
- Same-race groups
- Guild-only groups
- Configurable minimum levels
- Maximum-level exceptions
- Approved non-guild trade exceptions
- Guild Map position sharing

Rules only affect a character when iRC is active for that guild.

### Safe group enforcement

When an enabled race or guild-group rule is violated, iRC warns the player and explains the problem.

Hardcore safety is prioritized:

- Never automatically leaves during combat
- Never automatically leaves inside an instance
- Never automatically leaves while travelling by taxi
- Confirms violations with a delayed second check
- Protects existing groups when rules begin applying after login, reload, or level-up
- Clearly displays unresolved unsafe groups
- Records confirmed incidents for authorized officers

### Self-Found and Guild Found

iRC can verify whether characters meet the guild's configured Self-Found or Guild Found rules.

When Guild Found economy rules apply, iRC can:

- Allow transactions between verified guild members
- Support designated guild-bank and personal-bank characters
- Block unauthorized external trades and outgoing mail
- Prevent collecting restricted external mail
- Block Auction House use
- Monitor character money
- Record blocked actions and gold discrepancies for officer review
- Permit specifically configured non-guild trade exceptions

Guild Banks are managed through a synchronized list with comments showing who added each character and when.

### Guild Map

When enabled by the Guild Master, guild members can share temporary outdoor positions on the World Map.

- Personal controls for sharing your position and displaying guild members
- Class-colored markers
- Name, class, and level information
- No positions shared from instances
- No saved location history
- Lightweight, staggered updates

### Race Talk

Optional race-specific chat styles add readable roleplay flavor to messages you send.

Currently supported:

- Troll Talk
- Tauren Talk
- Night Elf Talk
- Undead Speak

## For Guild Masters and officers

### Guild configuration

The Guild Master can activate iRC and choose the features and optional rules appropriate for the guild. Normal guilds can use the shared information, statistics, onboarding, map, and officer features without enabling challenge restrictions.

Guild settings use verified authority and synchronization:

- Guild Master packages always have the highest authority
- Authorized officers can relay established settings when required
- Conflicting packages are validated by sender name and current guild rank
- Rulesets with matching timestamps must also have matching content
- Management changes use their own synchronized packages
- Background traffic and profanity checks are deferred during combat

### Delegated permissions

Guild Master features default to the Guild Master and rank 1, but the Guild Master can configure the lowest guild rank permitted to use individual systems, including:

- Verification decisions
- Presence checks and automatic warnings
- Incident history
- Guild Bank exceptions
- Welcome notifications
- Guild Homepage information and invite contacts

### Guild verification

The Verification panel shows the complete guild roster and identifies:

- Current iRC users
- Compatible RaceLocked users
- Missing or expired addon responses
- Incorrect character races when Race Lock is enabled
- Inactive Self-Found status when required
- Unverified Guild Found status when required
- Clean or flagged economy status
- Offline members
- Members requiring officer attention

Authorized officers can inspect reports, contact members about relevant rule violations, request fresh verification, and record manual decisions.

### Presence notifications and incidents

Eligible officer clients coordinate automatically so multiple officers do not send duplicate warnings.

iRC can record:

- Missing-addon warnings
- Race and group-rule violations
- Guild Found economy blocks
- Approved trade-exception activity
- Gold discrepancies
- Time, location, and involved players

Needs Attention changes notify eligible officers after a short combined delay, followed by periodic reminders while unresolved.

### Guild onboarding

Guild Masters and authorized officers can configure:

- Optional welcome messages
- Guild Homepage information
- Invite contacts with comments and attribution
- Up to five displayed invite contacts
- Clickable same-faction contact names that begin a whisper

## RaceLocked compatibility

iRC can coexist with RaceLocked and RaceLockedForkEU during migration.

Compatibility currently allows:

- Supported RaceLocked clients to appear as compatible
- iRC to answer compatible addon-presence checks
- Self-Found status exchange
- Correct identification of each report's actual source
- Continued use of iRC instead of RaceLocked where supported

iRC does not require RaceLocked, RaceLockedForkEU, or GuildFound and does not overwrite their saved data.

The original race-lock challenge concepts were inspired by RaceLocked, with credit to its creators for the idea. The Guild Found concepts were inspired by Guild Found, with credit to its creators for the idea.

Extra thanks to the Classic Era guild WE are FORSAKEN on EU Soulseeker for early addon testing.
