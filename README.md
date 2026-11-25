# Spoorloos Quiz Night

This is the full website project. GitHub Pages hosts the site, and Supabase holds the shared game data so the host, players, and leaderboard can connect from any network.

## Project files

- `index.html` - the player, host, and leaderboard screens
- `config.js` - your Supabase project URL and public publishable key
- `supabase/setup.sql` - database tables and secure game functions
- `.github/workflows/pages.yml` - automatic GitHub Pages deployment
- `spoorloos-wordmark.png` - Spoorloos trainwheel header wordmark
- `spoorloos-logo.jpg` - Spoorloos background watermark
- `floorplan.png` - clickable Garden, Stoep, Inside, H1, and H2 seating map

Keep these files together in the repository. In particular, include the hidden `.github` folder.

## Step 1: Create the Supabase database

1. Create a project at [Supabase](https://supabase.com/).
2. In the project dashboard, open **SQL Editor** and run the full contents of `supabase/setup.sql`. Re-run the updated file whenever this project adds database changes.
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

## Set up host sign-in

Only Supabase accounts explicitly added to `public.quiz_hosts` can open host controls.

1. In Supabase, open **Authentication > Users** and add the host with their email and a password.
2. Copy the new user's UUID from the Users list.
3. In **SQL Editor**, run `insert into public.quiz_hosts (user_id) values ('PASTE-USER-UUID-HERE');` using that UUID.
4. On the host tablet, choose **Open host controls** and sign in with that account.

Do not add a public sign-up form. To revoke host access, delete the user's row from `public.quiz_hosts`.

## Import a question list

Before creating a game, choose a `.txt`, `.csv`, or `.json` question file on the host setup screen. A text file uses one question per line; a CSV uses the first column for questions (an optional `Question` header is allowed); JSON uses an array of strings or objects with a `question` field. The file must contain 4–100 questions, each 500 characters or fewer. The question count is filled in automatically. The first question appears on the display when the game is created, and **Complete question - next** loads each following question automatically.
## Quiz night

After signing in on the tablet, the host chooses the number of questions (4–100) and creates the game. Host and player sessions are saved in that browser. If a player returns to the home screen, they can use **Continue game** to resume with the same code, name, and table. If the host leaves or reopens the site while the game is active, the existing game and code are restored; the host can create a new game after the current game ends. The six-digit game code is created once for that game and stays the same. Players can join from any network, choose their table on the floor plan, and wait for host approval. The MacBook leaderboard shows the code, current question, and progress. If a table answers incorrectly, its buzzer becomes available again and it can rejoin behind tables already waiting. At the start of the game and after every question, buzzers are closed. The host asks the question aloud, then presses **Start game** or **Activate buzzers** to open that round. A correct answer closes the buzzers until the host advances. After each question, the host selects **Complete question - next**. The app cues a reward at 25%, 50%, 75%, and 100% progress; the host records the table that receives each reward. Completing the final question ends the game automatically. The host can also choose **End game** at any time.

## Local preview

From this folder, run `python3 -m http.server 8000` and open `http://localhost:8000`. Configure Supabase first for the game features to work.






