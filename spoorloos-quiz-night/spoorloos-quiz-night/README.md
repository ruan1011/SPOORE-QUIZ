# Spoorloos Quiz Night

This is the full website project. GitHub Pages hosts the site, and Supabase holds the shared game data so the host, players, and leaderboard can connect from any network.

## Project files

- `index.html` - the player, host, and leaderboard screens
- `config.js` - your Supabase project URL and public publishable key
- `supabase/setup.sql` - database tables and secure game functions
- `.github/workflows/pages.yml` - automatic GitHub Pages deployment
- `spoorloos-logo.jpg` - Spoorloos logo
- `floorplan.png` - clickable Garden, Stoep, Inside, H1, and H2 seating map

Keep these files together in the repository. In particular, include the hidden `.github` folder.

## Step 1: Create the Supabase database

1. Create a project at [Supabase](https://supabase.com/).
2. In the project dashboard, open **SQL Editor** and run the contents of `supabase/setup.sql`.
3. Open **Project Settings > API Keys**. Copy the **Project URL** and **Publishable key**.
4. Open `config.js` in a text editor and replace `https://YOUR-PROJECT.supabase.co` and `YOUR-SUPABASE-PUBLISHABLE-KEY` with those values.

The publishable key is meant to appear in browser code. Do not put a Supabase secret key or service-role key in `config.js`.

## Step 2: Put the files in a GitHub repository

1. Create an empty repository on [GitHub](https://github.com/). A public repository is easiest for GitHub Pages.
2. Install and open GitHub Desktop, then choose **File > Clone repository** and clone the new repository to your computer.
3. Extract the Spoorloos ZIP file. Copy everything inside its `spoorloos-quiz-night` folder into the cloned repository folder. Make sure hidden files and folders are included, especially `.github/workflows/pages.yml`.
4. In GitHub Desktop, enter a summary such as `Add Spoorloos Quiz Night`, choose **Commit to main**, then click **Push origin**.

## Step 3: Turn on GitHub Pages

1. On GitHub, open your repository and go to **Settings > Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. Open the **Actions** tab and wait for **Deploy Spoorloos to GitHub Pages** to complete.
4. Find the published site address in **Settings > Pages** or the completed deployment workflow. It will look like `https://YOUR-USERNAME.github.io/YOUR-REPOSITORY/`.

Every push to the `main` branch will publish the latest site automatically.

## Quiz night

Open the published address on the host tablet and choose **Open host controls** to create a game. Share the six-digit code with players. The host can copy a separate leaderboard link to open on the MacBook. Players open the same site, enter the code, and tap their numbered table on the floor plan.

## Local preview

From this folder, run `python3 -m http.server 8000` and open `http://localhost:8000`. Configure Supabase first for the game features to work.
