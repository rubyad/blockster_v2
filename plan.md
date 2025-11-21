# BlocksterV2 Blog Platform Plan

## Project Overview
- Read To Earn blog platform that rewards users for reading and sharing articles
- User must create an account by signing up via Thirdweb which creates a Smart Wallet
- Users earn BUX points which they can redeem for entries into Airdrops, for discounts on merch in the store and discounts on Events tickets
- System tracks how long a reader spends on an article page and calculates their current BUX reward and adds to their Mnesia BUX balance
- User can claim his BUX points at any time by clicking on Mint BUX button which sets his Mnesia balance to zero and mints BUX on Rogue Chain and sends them to the user's connected wallet

## Pages List
- Homepage
- Article page
- Business page
- Editor page
- /admin page for managing users
- [TODO] admin version of posts/index where admin can select article from search to place in specific location in one of the top 2 sections of the homepage
- /hub page that displays all businesses
- /hubs/admin page that displays list of all business pages
- /hub/moonpay/admin page that lists all business's articles where admin can add BUX, edit Value, Contact
- Category page with infinite scroll sections system
- Tags page with infinite scroll sections system
- User profile page public
- User profile page private
- How It Works page
- Shop (powered by Shopify)
- Events (powered by Shopify)
- Bottom right widget LiveView BuxRewarder thats sticky across page loads that displays user's BUX earnings and activity
- Top right widget that displays user's wallet BUX balance

## Mechanics
- User visits homepage which displays articles, shop merch and events in dedicated sections
- Page loads two top sections then Store section then Events section then large image and after that infinite scroll system kicks in
- User scrolls down homepage and infinite scroll continually creates new sections with more content in them
- Sections can be by category or tag or user's known prefered tags or most recent or by hub or by author or any other fields available to the post
- The first 2 sections as displayed now on the homepage are latest news and Conversations and all posts that display in these 2 sections must be selected by an admin, done by admin clicking small icon in post area then selecting from search results
- On homepage user clicks on article which triggers a heartbeat using setInterval in hooks.js that sends message every second to central BUX Payer GenServer
- As long as BT is receiving heartbeat messages from a user from a specific article page BT calculates and edits new BUX balance for user and article
- On receiving heartbeat message (Article ID, user ID, fingerprint, timestamp), BUX Payer GenServer checks for existence of ets table for that article and adds user record and calculates user's BUX reward so far and edits user's and article's Mnesia BUX balances
- Every subsequent heartbeat message received creates new calculation of BUX reward and makes further edits to user's and article's BUX balance
- When user leaves that page the destroy part of hook clears the setInterval to stop the heartbeat messages being sent
- After user has received the maximum possible BUX reward for spending time on this article page then future heartbeat messages from this user on this article page are ignored
- ETS table for each article exists for 2 weeks and is then deleted. If an article's BUX balance is topped up before the ets table is deleted then users who have already received their max BUX reward for that article are not eligible to receive more of the topped up rewards. If article's BUX balance is topped up after the ets table is deleted there's no way to track which users already received BUX rewards and so all users are eligible to receive BUX
- Each article has a BUX balance, users get rewarded as long as BUX balance is positive
- Admin can top up article with more BUX if necessary
- BUX rewards are added by BuxPayer GenServer to the user's Mnesia record for his BUX balance and wallet address 
- User's Mnesia record should include his current BUX balance, total BUX earned, wallet address, email, membership status, 
- BUX are removed from the post's BUX balance in Mnesia and rewarded to article readers in real time by the BuxPayer GenServer until the post's BUX balance hits zero

## Account Creation 
- Account management by Thirdweb
- Users can sign up with their email, social login or regular wallet to create an account
- Each new user gets a Smart Wallet

## BuxTracker LiveView
- BuxTracker is a standalone LiveView process thats sticky across all page loads and displays bottom right of every page
- Clicking on it displays a larger popup area that shows more info about user's activity and BUX earnings for this article by default or for all articles
- It displays info that it's pulling from Mnesia, the actual rewards are calculated and made in Mnesia by BuxPayer GenServer
- New page mount pings bux_tracker with article ID which it uses to lookup Mnesia for remaining BUX balance and user's current BUX earnings
- User is rewarded every second by BuxPayer GS which is updated in real time in BuxTracker LV
- BT has a Mint BUX button that transfers pending BUX rewards on-chain to user's wallet and sets Mnesia BUX balance to zero

## Mnesia
- Every article has an Mnesia record that holds its current BUX balance, total BUX deposited, standard reward, read time, share rate (BUX reward per social share) 
- The standard reward is multiplied by the user's multiplier, meaning that users can make more than the standard if they have a good quality profile
- The social share reward is the standard amount which is then increased according to the quality of the user's social media account on which he is sharing the article
- Read time is the minimum amount of time the user must spend on the page to receive the full reward. Rewards are calculated and edited in Mnesia every second by Bux Payer GS
- {:post_balances, :bux_balance, bux_total_deposited, :standard_reward, :read_time, :social_share_reward, :facebook_multiplier, :x_multiplier, :linkedin_multiplier, :telegram_multiplier}
- Every user has an Mnesia record that holds his current outstanding BUX balance, total BUX earned, wallet address, email, multiplier, updated at, created at
- A user's multiplier increases his received reward from an article and is increased by the quality of his profile - more connected social media accounts and a verified email increase the multiplier resulting in higher BUX rewards
- {:user_balances, :bux_balance, :bux_total_earned, :wallet, :email, :multiplier, :extra_field_1, :extra_field_2, :updated_at, :created_at}
- Also need mnesia record for every hub which can also have a BUX balance and settings to reward that balance to new followers
- {:hub_balances, :bux_balance, :bux_total_deposited, :new_follower_reward, :rewards_active, }

## Email Capture Landing Page
- Single page with no external links with marketing slogan and email capture field in main header
- User enters email and presses Submit button which then changes main header content to text confirmation message saying please check email
- In your email inbox there's a message that says thanks and please verify your email by clicking on the link
- Save every email in postgres table called emails, with verified status field true if user verifies email
- Create admin page to view and copy and download as csv email addresses who have signed up
- Host on blockster.com/v2 using CNAME

## Tracking URLs
- Add ?ref=user_id to urls shared by users and record how many visits each url gets in a separate Mnesia table and use this info to dynamically adjust the user's social multipliers

## BuxPayer GenServer
- GenServer that receives heartbeat messages from hooks and then calculates and edits article's and users' BUX balances in Mnesia only
- Maintains ets table for every article and keeps a record of every user who has earned BUX rewards and how much so far
- GS does an update to Mnesia records of article and users after every heartbeat message it receives
- Only this single GS does Mnesia BUX updates for all articles and all users
- Admin has function to send any amount of BUX to any user which is just a Mnesia balance edit
- Admin can add any amount of BUX to any article's BUX balance which is just a Mnesia balance edit
- Only when user clicks on Mint BUX button do actual BUX tokens get minted and sent to the user's wallet by the BUX token smart contract, but that blockchain tx is done with a different GenServer called BuxMinter

## Use Hooks.js
- Create hooks.js and use

## BuxMinter GenServer
- Receives messages to mint BUX on-chain and send them to a user's wallet
- Does this by using nodejs app to send function call to BUX Token smart contract
- User's Mnesia BUX balance is first reduced in BuxPayer GS which then sends message to BuxMinter GS 
- Message to here must be cast to prevent this slow tx from blocking BuxPayer's highly active system - how to confirm tx?

## Social Media API Connections
- User should be able to connect his social media accounts to his Blockster account so he can share articles and get rewarded BUX for doing so
- This functionality should be on user's profile page where it shows his connected social media accounts

## Search Articles
- User can start typing in box and dropdown of possible articles display
- Integrate this into admin's homepage where he can select from search result which article is displayed in selected spot

## Airdrop Claim System
- Users can redeem some or all of their BUX balance to get a share of a weekly airdrop of tokens sponsored by hub company

## Web3 Functionality
- Sign in system built with Thirdweb
- User can connect his wallet or create wallet with an email or social login which creates Smart Wallet
- User's BUX balance on chain is displayed top right
- When user clicks Mint BUX button the BUX token smart contract pays the full token balance on-chain to the user's wallet address 
- User can send BUX from his blockster account wallet to any other wallet (if he signed up with email this is only way to send them)

## BUX Token Smart Contract
- Upgradeable contract where owner assigned admin can mint and burn BUX tokens on demand
- Receives function calls from BuxPayer

## Business Pages
- Approved companies can create a business page that appears in the Hub area
- Page displays articles by that business
- Page can also display merch and events by that company
- Business pays $250 per article published which includes 250,000 BUX points deposited into the post's BUX balance
- Or business can do subscription which includes x articles per month with x BUX points added to each
- Admin will add the BUX to the article on creation on Editor page
- Send admin notification with each sale
- Accept payments for page subscriptions and articles through Stripe and Helio
- 250k BUX deposit is done in Mnesia only to each post
- Rewards are paid on-chain when claimed by the user and the Mnesia record's BUX balance reduces to zero
- Admin can add any amount of BUX to this business page which can be rewarded to new signups or any users who follow this page

## Business Page Followers System
- Users can follow and unfollow hubs
- Already related in db so followers and hubs can be preloaded in Repo queries
- Admin can add BUX balance to a hub and adjust settings to reward it in real-time to new signups and any user who follows this page

## Shopify Integration
- The Blockster Store and the Events functionality will be built and hosted using Shopify
- User can redeem some or all of his BUX points to receive a discount code for a product and then he buys on Shopify system

# Editor Page
- Admin can add any amount of BUX to a post by calling BuxPayer GenServer
- Add new form fields for new fields in posts
- Add new fields in left sidebar at top: BUX Balance, Total BUX, Post Value (formatted into USD), Contact, and make sure their values dont get set to nil on post save if the user does not change them
- 

## Infinite Scroll System
- Creates new sections containing posts and displays them on homepage as user scrolls down page
- Must also work on category page, tag page

## Layer Zero Bridge
- Hub companies giving away airdrops of their token or rewarding with their token instead of BUX must bridge their token to Rogue Chain
- Users redeem some or all of their on-chain BUX points to enter the competition to get a share of the airdrop
- Users receive their share of the airdropped tokens on Rogue Chain

## Account Abstraction
- Smart Wallet pays all ROGUE gas costs of all BUX txs







