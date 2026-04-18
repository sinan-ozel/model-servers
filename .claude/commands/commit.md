---
allowed-tools: Bash(git diff *), Bash(git commit *), Bash(!git add *), Edit(!*), Write(!*)
---

Run `git diff --staged`

Analyze all of it, git commit with a good message.
Do not add anything. Do not add anything, just look at what is staged.
We are looking for a 50-character summary on top, detailed information below.

Separate subject from body with a blank line
Limit the subject line to 50 characters
Capitalize the subject line
Do not end the subject line with a period
Use the imperative mood in the subject line
Wrap the body at 72 characters
Use the body to explain what and why vs. how

Do not ask for permission, just write the commit.
