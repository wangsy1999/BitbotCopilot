# Project workflow

- After modifying the macOS client and successfully building and packaging it, automatically open `macOS/output/Bitbot Copilot.app` as part of delivery. Do not leave launching the app as a manual step for the user.
- If an older build is already running, restart the Bitbot Copilot client to load the new build; merely calling `open` activates the old process. Tell the user that restarting requires reconnecting the robot.
