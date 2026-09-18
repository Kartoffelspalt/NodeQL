# NodeQL Workshop Update — Learn SQLite Interactively with Real Nodes

This release introduces a fully integrated, interactive NodeQL Workshop. Instead of answering traditional quiz questions, users learn SQLite directly inside the real NodeQL workspace by selecting, configuring, dragging, and connecting nodes into valid queries.

## Interactive Workshop

- Dedicated Workshop mode inside the NodeQL window
- Fully isolated from the regular project workspace
- Familiar layout with node palette, canvas, query tabs, and SQL output
- Open projects, databases, settings, and undo history remain untouched
- Every Workshop session starts with a fresh workspace
- Learning progress is saved across sessions

## Learn SQLite Step by Step

The first learning path provides an approximately 15-minute guided introduction in Simple Mode. Seven short missions cover:

1. The start node and `SELECT`
2. Inserted `COLUMN` reporter nodes
3. Filtering rows with `WHERE`
4. `TEXT` nodes and typed values
5. Combining conditions with `AND`
6. Sorting results with `ORDER BY`
7. Limiting results with `LIMIT`

Every mission includes:

- Clear explanations of the relevant nodes
- Short, practical exercises
- Immediate live feedback
- Visible mission progress
- Contextual hints
- Target SQL and live-generated SQLite
- Automatic selection of the relevant node category
- Estimated completion time
- A clear indication of the next missing requirement

## Simple Mode and SQLite Syntax

Workshop explanations now display the actual labels used by NodeQL:

- The beginner-friendly Simple Mode label
- The corresponding Advanced Mode and SQLite label
- The purpose of each node
- Its position within a valid query

This helps users understand both the visual node system and the underlying SQLite syntax.

## Improved Node Recognition

Mission validation now correctly recognizes:

- Direct input values
- Column and text reporter nodes
- Nested aggregate reporters
- Structured filter conditions
- Complete `JOIN` conditions
- `GROUP BY` and `HAVING`
- `ORDER BY` with valid sort directions
- Positive `LIMIT` values
- `UNION` queries
- Correct SQL clause order

Only nodes connected to `EXECUTE QUERY` are evaluated. Loose nodes elsewhere on the canvas cannot accidentally complete a mission.

## Quality and Stability

- Fully isolated Workshop workspace, tabs, runtime, and SQL mode
- Simple and Advanced switching without modifying the global preference
- Responsive Workshop interface
- Scrollable explanations with permanently accessible actions
- Existing project and tutorial progress formats remain compatible
- 191 automated tests passing
- `flutter analyze` reports no issues
