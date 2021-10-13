Combat Modifier Calculation

This extension automatically calulates common modifiers in combat.

What it does:
Adds buttons to the Modifiers window for shooting into melee and flanking.
Puts buttons on the desktop for the three levels of cover, shooting into melee, flanking, and flat-footed.

For a ranged attack:
If the range is 30' or less and the attacker has the Point Blank Shot feat, adds effect "pbs; ATK: 1 ranged, DMG: 1 ranged, DMGS: 1"
If the range is 30' or less and the attacker doesn't have the feat, adds effect "pbs" (for facilitating Sneak Attack)
Removes the above effects if range is greater than 30'
Calculates range penalty based on number of range increments
Displays a warning in Chat if beyond maximum range (this does not prevent the attack)
Calculates "shooting into melee" penalty (using the PF1e rules, not 3.5E)

For a PC the weapon range is taken right from the inventory list so if a weapon has a custom name, the Distance ability, etc., the calculations will still work.  For an NPC, as long as the weapon name includes the base for the weapon it will find the correct range (so Shortbow, Masterwork Shortbow, +1 Shortbow, Flaming Shortbow of Spiked Intrusion, etc. will all use the range for "shortbow").

For a melee attack:
Determines whether or not the attacker is flanking the target; if so, adds the +2 bonus and adds effect "Flanking" to the attacker (again, for Sneak Attack)
Removes "Flanking" effect if the attacker isn't flanking

What it doesn't do:
Flanking is calculated based on allies and their size and natural reach.  It does not take into account whether or not an ally has a reach weapon or if they don't have a melee weapon at all.
Flanking doesn't take occuluders into account.  If a goblin is attacking and its allied ogre is 10' from the target with a wall in between, the goblin will still get the flanking bonus.

Cover.  I had considered working to automate cover modifiers, but decided against it because, at least at the tables I've played on, it is never treated exactly like in the rules; many pretty much just ignore cover unless it's from a wall or other object (does a size 0 attacker, shooting past/through a size 0 creature, suffer a partial or full cover penalty, or none at all?).  I didn't want this extension to force a group to play it a certain way.

My goal was to get the vast majority of situtations to work correctly, and based on my testing it does that.  I'll find out for sure in a few days at my next gaming session.

Compatibility:
I use very few extensions, so I have not widely checked compatibility.
This extension replaces ActionAttack.modAttack, but it does call the original, so it should still be compatible with other extentions affecting that function (provided they modify, rather than replace, it).

One extention I would rather not live without is Kelrugem's Full Extension Overlay; this extension does not conflict with it.
