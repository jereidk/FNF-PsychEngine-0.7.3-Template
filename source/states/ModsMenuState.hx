package states;

import backend.WeekData;
import backend.Mods;

import flixel.ui.FlxButton;
import flixel.FlxBasic;
import flixel.graphics.FlxGraphic;
import flash.geom.Rectangle;
import lime.utils.Assets;
import haxe.Json;

import flixel.util.FlxSpriteUtil;
import objects.AttachedSprite;
import options.ModSettingsSubState;
import flixel.addons.transition.FlxTransitionableState;

class ModsMenuState extends MusicBeatState
{
	var bg:FlxSprite;
	var icon:FlxSprite;
	var modName:Alphabet;
	var modVersion:FlxText;
	var modDesc:FlxText;
	var modIssues:FlxText;
	var modRestartText:FlxText;
	var modsList:ModsList = null;
	var modCount:Int = 0; // real mods, not counting the base game entry

	var bottomText:FlxText;
	var searchText:FlxText;
	var searching:Bool = false;
	var searchQuery:String = '';

	var bgList:FlxSprite;
	var buttonReload:MenuButton;
	//var buttonModFolder:MenuButton;
	var buttonEnableAll:MenuButton;
	var buttonDisableAll:MenuButton;
	var buttons:Array<MenuButton> = [];
	var moveButtons:Array<MenuButton> = [];
	var settingsButton:MenuButton;
	var toggleButton:MenuButton;

	var bgTitle:FlxSprite;
	var bgDescription:FlxSprite;
	var bgButtons:FlxSprite;

	var modsGroup:FlxTypedGroup<ModItem>;
	var curSelectedMod:Int = 0;
	
	var hoveringOnMods:Bool = true;
	var curSelectedButton:Int = 0; ///-1 = Enable/Disable All, -2 = Reload
	var modNameInitialY:Float = 0;

	var noModsSine:Float = 0;
	var noModsTxt:FlxText;

	var _lastControllerMode:Bool = false;
	var startMod:String = null;
	public function new(startMod:String = null)
	{
		this.startMod = startMod;
		super();
	}
	override function create()
	{
		var daButton:String = "BACKSPACE";

		if (controls.mobileC)
			daButton = 'B';
		
		// Reaching the launcher means you left whatever mod you were in, so its assets go away
		// and the menu itself is drawn with the base game's
		Mods.exitMod();

		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		persistentUpdate = false;

		modsList = Mods.parseList();
		modCount = modsList.all.length;

		// The base game is listed like any other mod, so everything is launched the same way.
		// It's pinned at the top and can't be moved, toggled or saved to modsList.txt.
		modsList.all.insert(0, Mods.BASE_GAME);

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF665AFF;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();

		bgList = FlxSpriteUtil.drawRoundRect(new FlxSprite(40, 40).makeGraphic(340, 440, FlxColor.TRANSPARENT), 0, 0, 340, 440, 15, 15, FlxColor.BLACK);
		bgList.alpha = 0.6;

		modsGroup = new FlxTypedGroup<ModItem>();

		for (i => mod in modsList.all)
		{
			if(startMod == mod) curSelectedMod = i;

			var modItem:ModItem = new ModItem(mod);
			if(modsList.disabled.contains(mod))
			{
				modItem.icon.color = 0xFFFF6666;
				modItem.text.color = FlxColor.GRAY;
			}
			modsGroup.add(modItem);
		}

		var mod:ModItem = modsGroup.members[curSelectedMod];
		if(mod != null) bg.color = mod.bgColor;

		//
		var buttonX = bgList.x;
		var buttonWidth = Std.int(bgList.width);
		var buttonHeight = 80;
		var daY = 0;
		
		if(controls.mobileC)
			daY = 70;
		else
			daY = 20;

		buttonReload = new MenuButton(buttonX, bgList.y + bgList.height + daY, buttonWidth, buttonHeight, "RELOAD", reload);
		add(buttonReload);
		
		var myY = buttonReload.y + buttonReload.bg.height + 20;
		/*buttonModFolder = new MenuButton(buttonX, myY, buttonWidth, buttonHeight, "MODS FOLDER", function() {
			var modFolder = Paths.mods();
			if(!FileSystem.exists(modFolder))
			{
				trace('created missing folder');
				FileSystem.createDirectory(modFolder);
			}
			CoolUtil.openFolder(modFolder);
		});
		add(buttonModFolder);*/

		buttonEnableAll = new MenuButton(buttonX, myY, buttonWidth, buttonHeight, "ENABLE ALL", function() {
			buttonEnableAll.ignoreCheck = false;
			for (mod in modsGroup.members)
			{
				if(modsList.disabled.contains(mod.folder))
				{
					modsList.disabled.remove(mod.folder);
					modsList.enabled.push(mod.folder);
					mod.icon.color = FlxColor.WHITE;
					mod.text.color = FlxColor.WHITE;
				}
			}
			updateModDisplayData();
			checkToggleButtons();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		buttonEnableAll.bg.color = FlxColor.GREEN;
		buttonEnableAll.focusChangeCallback = function(focus:Bool) if(!focus) buttonEnableAll.bg.color = FlxColor.GREEN;
		
		if(!controls.mobileC)
			add(buttonEnableAll);

		buttonDisableAll = new MenuButton(buttonX, myY, buttonWidth, buttonHeight, "DISABLE ALL", function() {
			buttonDisableAll.ignoreCheck = false;
			for (mod in modsGroup.members)
			{
				if(modsList.enabled.contains(mod.folder))
				{
					modsList.enabled.remove(mod.folder);
					modsList.disabled.push(mod.folder);
					mod.icon.color = 0xFFFF6666;
					mod.text.color = FlxColor.GRAY;
				}
			}
			updateModDisplayData();
			checkToggleButtons();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		buttonDisableAll.bg.color = 0xFFFF6666;
		buttonDisableAll.focusChangeCallback = function(focus:Bool) if(!focus) buttonDisableAll.bg.color = 0xFFFF6666;
		
		if(!controls.mobileC)
			add(buttonDisableAll);
		
		checkToggleButtons();

		if(modCount < 1)
		{
			// The base game is still there to enter, so the menu stays fully usable. update()
			// keeps polling so a mod dropped into the folder shows up without leaving the menu.
			buttonEnableAll.visible = buttonEnableAll.enabled = false;
			buttonDisableAll.visible = buttonDisableAll.enabled = false;
			FlxG.autoPause = false;
		}
		//

		bgTitle = FlxSpriteUtil.drawRoundRectComplex(new FlxSprite(bgList.x + bgList.width + 20, 40).makeGraphic(840, 180, FlxColor.TRANSPARENT), 0, 0, 840, 180, 15, 15, 0, 0, FlxColor.BLACK);
		bgTitle.alpha = 0.6;
		add(bgTitle);

		icon = new FlxSprite(bgTitle.x + 15, bgTitle.y + 15);
		add(icon);

		modNameInitialY = icon.y + 80;
		modName = new Alphabet(icon.x + 165, modNameInitialY, "", true);
		modName.scaleY = 0.8;
		add(modName);

		modVersion = new FlxText(icon.x + 168, bgTitle.y + bgTitle.height - 42, 620, "", 18);
		modVersion.setFormat(Paths.font("vcr.ttf"), 18, 0xFFB4B4B4, LEFT);
		add(modVersion);

		bgDescription = FlxSpriteUtil.drawRoundRectComplex(new FlxSprite(bgTitle.x, bgTitle.y + 200).makeGraphic(840, 450, FlxColor.TRANSPARENT), 0, 0, 840, 450, 0, 0, 15, 15, FlxColor.BLACK);
		bgDescription.alpha = 0.6;
		add(bgDescription);
		
		modDesc = new FlxText(bgDescription.x + 15, bgDescription.y + 15, bgDescription.width - 30, "", 24);
		modDesc.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT);
		add(modDesc);

		// Broken pack.json, missing dependencies and the like get listed right under the description
		modIssues = new FlxText(bgDescription.x + 15, bgDescription.y + 15, bgDescription.width - 30, "", 20);
		modIssues.setFormat(Paths.font("vcr.ttf"), 20, 0xFFFF6666, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		modIssues.borderSize = 1;
		add(modIssues);

		var myHeight = 100;
		modRestartText = new FlxText(bgDescription.x + 15, bgDescription.y + bgDescription.height - myHeight - 25, bgDescription.width - 30, "* Moving or Toggling On/Off this Mod will restart the game.", 16);
		modRestartText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, RIGHT);
		add(modRestartText);

		bgButtons = FlxSpriteUtil.drawRoundRectComplex(new FlxSprite(bgDescription.x, bgDescription.y + bgDescription.height - myHeight).makeGraphic(840, myHeight, FlxColor.TRANSPARENT), 0, 0, 840, myHeight, 0, 0, 15, 15, FlxColor.WHITE);
		bgButtons.color = FlxColor.BLACK;
		bgButtons.alpha = 0.2;
		add(bgButtons);

		var buttonsX = bgButtons.x + 320;
		var buttonsY = bgButtons.y + 10;

		// Position 1, not 0: the base game entry is pinned to the top of the list
		var button = new MenuButton(buttonsX, buttonsY, 80, 80, Paths.image('modsMenuButtons'), function() moveModToPosition(1), 54, 54); //Move to the top
		button.icon.animation.add('icon', [0]);
		button.icon.animation.play('icon', true);
		add(button);
		buttons.push(button);
		moveButtons.push(button);

		var button = new MenuButton(buttonsX + 100, buttonsY, 80, 80, Paths.image('modsMenuButtons'), function() moveModToPosition(curSelectedMod - 1), 54, 54); //Move up
		button.icon.animation.add('icon', [1]);
		button.icon.animation.play('icon', true);
		add(button);
		buttons.push(button);
		moveButtons.push(button);

		var button = new MenuButton(buttonsX + 200, buttonsY, 80, 80, Paths.image('modsMenuButtons'), function() moveModToPosition(curSelectedMod + 1), 54, 54); //Move down
		button.icon.animation.add('icon', [2]);
		button.icon.animation.play('icon', true);
		add(button);
		buttons.push(button);
		moveButtons.push(button);

		settingsButton = new MenuButton(buttonsX + 300, buttonsY, 80, 80, Paths.image('modsMenuButtons'), function() //Settings
		{
			var curMod:ModItem = modsGroup.members[curSelectedMod];
			if(curMod != null && curMod.settings != null && curMod.settings.length > 0)
			{
				openSubState(new ModSettingsSubState(curMod.settings, curMod.folder, curMod.name));
			}
		}, 54, 54);

		settingsButton.icon.animation.add('icon', [3]);
		settingsButton.icon.animation.play('icon', true);
		add(settingsButton);
		buttons.push(settingsButton);

		if(modsGroup.members[curSelectedMod].settings == null || modsGroup.members[curSelectedMod].settings.length < 1)
			settingsButton.enabled = false;

		toggleButton = new MenuButton(buttonsX + 400, buttonsY, 80, 80, Paths.image('modsMenuButtons'), function() //On/Off
		{
			var curMod:ModItem = modsGroup.members[curSelectedMod];
			if(curMod == null || curMod.folder == Mods.BASE_GAME) return; // the base game can't be turned off

			var mod:String = curMod.folder;
			if(!modsList.disabled.contains(mod)) //Enable
			{
				modsList.enabled.remove(mod);
				modsList.disabled.push(mod);
			}
			else //Disable
			{
				modsList.disabled.remove(mod);
				modsList.enabled.push(mod);
			}
			curMod.icon.color = modsList.disabled.contains(mod) ? 0xFFFF6666 : FlxColor.WHITE;
			curMod.text.color = modsList.disabled.contains(mod) ? FlxColor.GRAY
				: (curMod.hasFatalIssues ? 0xFFFFCC44 : FlxColor.WHITE);

			if(curMod.mustRestart) waitingToRestart = true;
			updateModDisplayData();
			checkToggleButtons();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}, 54, 54);
		toggleButton.icon.animation.add('icon', [4]);
		toggleButton.icon.animation.play('icon', true);
		add(toggleButton);
		buttons.push(toggleButton);
		toggleButton.focusChangeCallback = function(focus:Bool) {
			if(!focus)
				toggleButton.bg.color = modsList.enabled.contains(modsList.all[curSelectedMod]) ? FlxColor.GREEN : 0xFFFF6666;
		};

		#if desktop
		// The left half of the button bar was empty, so the mods folder shortcut lives there
		var folderButton = new MenuButton(bgButtons.x + 10, buttonsY, 300, 80, "MODS FOLDER", openModsFolder);
		add(folderButton);
		buttons.push(folderButton);
		#end

		add(bgList);
		add(modsGroup);

		if(modCount < 1)
		{
			// Goes on top of the list panel, under the base game entry
			noModsTxt = new FlxText(bgList.x + 15, bgList.y + 105, bgList.width - 30,
				"No mods installed.\nDrop one into the mods\nfolder and it shows up here.", 16);
			noModsTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			noModsTxt.borderSize = 2;
			add(noModsTxt);
		}

		_lastControllerMode = controls.controllerMode;

		changeSelectedMod();

		var bottomBG = new FlxSprite(0, FlxG.height - 26).makeGraphic(FlxG.width, 26, 0xFF000000);
		bottomBG.alpha = 0.6;
		add(bottomBG);

		var acceptButton:String = controls.mobileC ? "A" : "ENTER";
		var leaveHint:String = "Press " + acceptButton + " To Play     Press " + daButton + " To Leave";
		#if desktop
		if(!controls.mobileC && modCount > 0) leaveHint += "     Press TAB To Search";
		#end

		bottomText = new FlxText(bottomBG.x, bottomBG.y + 4, FlxG.width, leaveHint, 16);
		bottomText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
		bottomText.scrollFactor.set();
		add(bottomText);

		searchText = new FlxText(bottomBG.x, bottomBG.y + 4, FlxG.width, "", 16);
		searchText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.YELLOW, CENTER);
		searchText.scrollFactor.set();
		searchText.visible = false;
		add(searchText);

		#if mobile
		addTouchPad("UP_DOWN", "A_B"); // A enters the selected mod, B leaves the menu
		touchPad.y -= 215; // so that you can press the buttons.
		#end
		
		if(controls.mobileC)
			touchPad.alpha = 0.3;
		
		super.create();
	}
	
	var nextAttempt:Float = 1;
	var holdingMod:Bool = false;
	var mouseOffsets:FlxPoint = new FlxPoint();
	var holdingElapsed:Float = 0;
	var gottaClickAgain:Bool = false;

	var holdTime:Float = 0;
	var exiting:Bool = false;
	override function update(elapsed:Float)
	{
		// Search takes over the keyboard while it's open, so it gets first say
		if(searching)
		{
			updateSearch();
			super.update(elapsed);
			return;
		}
		else if(!controls.mobileC && !exiting && modsList.all.length > 1 && FlxG.keys.justPressed.TAB)
		{
			searching = true;
			searchQuery = '';
			updateSearchText();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			super.update(elapsed);
			return;
		}

		if(controls.BACK && hoveringOnMods && !exiting)
		{
			exiting = true;
			if(colorTween != null) {
				colorTween.cancel();
			}
			saveTxt();

			FlxG.sound.play(Paths.sound('cancelMenu'));
			if(waitingToRestart)
			{
				//MusicBeatState.switchState(new TitleState());
				TitleState.initialized = false;
				TitleState.closedState = false;
				FlxG.sound.music.fadeOut(0.3);
				if(FreeplayState.vocals != null)
				{
					FreeplayState.vocals.fadeOut(0.3);
					FreeplayState.vocals = null;
				}
				FlxG.camera.fade(FlxColor.BLACK, 0.5, false, FlxG.resetGame, false);
			}
			else MusicBeatState.switchState(new MainMenuState());

			persistentUpdate = false;
			FlxG.autoPause = ClientPrefs.data.autoPause;
			FlxG.mouse.visible = false;
			return;
		}

		if(Math.abs(FlxG.mouse.deltaX) > 10 || Math.abs(FlxG.mouse.deltaY) > 10)
		{
			controls.controllerMode = false;
			if(!FlxG.mouse.visible) FlxG.mouse.visible = true;
		}
		
		if(controls.controllerMode != _lastControllerMode)
		{
			if(controls.controllerMode) FlxG.mouse.visible = false;
			_lastControllerMode = controls.controllerMode;
		}

		if(controls.UI_DOWN_R || controls.UI_UP_R) holdTime = 0;

		if(modCount < 1)
		{
			noModsSine += 180 * elapsed;
			noModsTxt.alpha = 1 - Math.sin((Math.PI * noModsSine) / 180);

			// Keep refreshing the mod list every second until a mod shows up in the folder
			nextAttempt -= elapsed;
			if(nextAttempt < 0)
			{
				nextAttempt = 1;
				@:privateAccess
				Mods.updateModList();

				var refreshed:ModsList = Mods.parseList();
				if(refreshed.all.length > 0)
				{
					trace('mod(s) found! reloading');

					// Take the fresh list over, otherwise reload() would save the stale one
					// back out and wipe the mod that was just found
					modsList = refreshed;
					modsList.all.insert(0, Mods.BASE_GAME);
					reload();
					return;
				}
			}
		}

		// List input. The base game entry means the list is never empty, so this always runs
		{
			if(controls.controllerMode && holdingMod)
			{
				holdingMod = false;
				holdingElapsed = 0;
				updateItemPositions();
			}
			var lastMode = hoveringOnMods;
			if(modsList.all.length > 1)
			{
				if(!controls.mobileC && FlxG.mouse.justPressed)
				{
					for (i in centerMod-2...centerMod+3)
					{
						var mod = modsGroup.members[i];
						if(mod != null && mod.visible && FlxG.mouse.overlaps(mod))
						{
							hoveringOnMods = true;
							var button = getButton();
							button.ignoreCheck = button.onFocus = false;
							mouseOffsets.x = FlxG.mouse.x - mod.x;
							mouseOffsets.y = FlxG.mouse.y - mod.y;
							curSelectedMod = i;
							changeSelectedMod();
							break;
						}
					}
					hoveringOnMods = true;
					var button = getButton();
					button.ignoreCheck = button.onFocus = false;
					gottaClickAgain = false;
				}

				if(hoveringOnMods)
				{
					var shiftMult:Int = (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyPressed(LEFT_SHOULDER) || FlxG.gamepads.anyPressed(RIGHT_SHOULDER)) ? 4 : 1;
					if(controls.UI_DOWN_P)
						changeSelectedMod(shiftMult);
					else if(controls.UI_UP_P)
						changeSelectedMod(-shiftMult);
					else if(FlxG.mouse.wheel != 0)
						changeSelectedMod(-FlxG.mouse.wheel * shiftMult, true);
					else if(FlxG.keys.justPressed.HOME || FlxG.keys.justPressed.END ||
						FlxG.gamepads.anyJustPressed(LEFT_TRIGGER) || FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER))
					{
						if(FlxG.keys.justPressed.END || FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER)) curSelectedMod = modsList.all.length-1;
						else curSelectedMod = 0;
						changeSelectedMod();
					}
					else if(controls.UI_UP || controls.UI_DOWN)
					{
						var lastHoldTime:Float = holdTime;
						holdTime += elapsed;
						if(holdTime > 0.5 && Math.floor(lastHoldTime * 8) != Math.floor(holdTime * 8)) changeSelectedMod(shiftMult * (controls.UI_UP ? -1 : 1));
					}

					else if(FlxG.mouse.pressed && !controls.mobileC && !gottaClickAgain)
					{
						var curMod:ModItem = modsGroup.members[curSelectedMod];
						if(curMod != null)
						{
							if(!holdingMod && FlxG.mouse.justMoved && FlxG.mouse.overlaps(curMod)) holdingMod = true;

							if(holdingMod)
							{
								var moved:Bool = false;
								for (i in centerMod-2...centerMod+3)
								{
									var mod = modsGroup.members[i];
									if(i > 0 && mod != null && mod.visible && FlxG.mouse.overlaps(mod) && curSelectedMod != i)
									{
										moveModToPosition(i);
										moved = true;
										break;
									}
								}
								
								if(!moved)
								{
									var factor:Float = -1;
									if(FlxG.mouse.y < bgList.y)
										factor = Math.abs(Math.max(0.2, Math.min(0.5, 0.5 - (bgList.y - FlxG.mouse.y) / 100)));
									else if(FlxG.mouse.y > bgList.y + bgList.height)
										factor = Math.abs(Math.max(0.2, Math.min(0.5, 0.5 - (FlxG.mouse.y - bgList.y - bgList.height) / 100)));
		
									if(factor >= 0)
									{
										holdingElapsed += elapsed;
										if(holdingElapsed >= factor)
										{
											holdingElapsed = 0;
											var newPos = curSelectedMod;
											if(FlxG.mouse.y < bgList.y) newPos--;
											else newPos++;
											moveModToPosition(Std.int(Math.max(1, Math.min(modsGroup.length - 1, newPos))));
										}
									}
								}
								curMod.x = FlxG.mouse.x - mouseOffsets.x;
								curMod.y = FlxG.mouse.y - mouseOffsets.y;
							}
						}
						
					}
					else if(FlxG.mouse.justReleased && !controls.mobileC && holdingMod)
					{
						holdingMod = false;
						holdingElapsed = 0;
						updateItemPositions();
					}
				}
			}

			if(lastMode == hoveringOnMods)
			{
				if(hoveringOnMods)
				{
					if(controls.ACCEPT)
					{
						enterSelectedMod();
						return;
					}
					else if(controls.UI_RIGHT_P)
					{
						hoveringOnMods = false;
						var button = getButton();
						button.ignoreCheck = button.onFocus = false;
						curSelectedButton = 0;
						changeSelectedButton();
					}
				}
				else 
				{
					if(controls.BACK)
					{
						hoveringOnMods = true;
						var button = getButton();
						button.ignoreCheck = button.onFocus = false;
						changeSelectedMod();
					}
					else if(controls.ACCEPT)
					{
						var button = getButton();
						if(button.onClick != null) button.onClick();
					}
					else if(curSelectedButton < 0)
					{
						if(controls.UI_UP_P)
						{
							switch(curSelectedButton)
							{
								case -2:
									curSelectedMod = 0;
									hoveringOnMods = true;
									var button = getButton();
									button.ignoreCheck = button.onFocus = false;
									changeSelectedMod();
								case -1:
									changeSelectedButton(-1);
							}
						}
						else if(controls.UI_DOWN_P)
						{
							switch(curSelectedButton)
							{
								case -2:
									changeSelectedButton(1);
								case -1:
									curSelectedMod = 0;
									hoveringOnMods = true;
									var button = getButton();
									button.ignoreCheck = button.onFocus = false;
									changeSelectedMod();
							}
						}
						else if(controls.UI_RIGHT_P)
						{
							var button = getButton();
							button.ignoreCheck = button.onFocus = false;
							curSelectedButton = 0;
							changeSelectedButton();
						}
					}
					else if(controls.UI_LEFT_P)
						changeSelectedButton(-1);
					else if(controls.UI_RIGHT_P)
						changeSelectedButton(1);
				}
			}
		}
		super.update(elapsed);
	}

	/**
	 * Launches whatever is selected: a mod, or the base game.
	 * The game is reset so nothing loaded before the switch survives, and it comes back up on
	 * TitleState, which is now the mod's own title screen, main menu, story mode and freeplay.
	 */
	function enterSelectedMod()
	{
		if(exiting) return;

		var curMod:ModItem = modsGroup.members[curSelectedMod];
		if(curMod == null) return;

		var isBase:Bool = (curMod.folder == Mods.BASE_GAME);
		if(!isBase && modsList.disabled.contains(curMod.folder))
		{
			// Turn it on first, otherwise none of its content would load
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		exiting = true;
		saveTxt();
		Mods.enterMod(isBase ? '' : curMod.folder);

		FlxG.sound.play(Paths.sound('confirmMenu'));
		if(colorTween != null) colorTween.cancel();

		persistentUpdate = false;
		FlxG.autoPause = ClientPrefs.data.autoPause;
		FlxG.mouse.visible = false;

		// Same restart path the menu already used for mods that ask for one
		TitleState.initialized = false;
		TitleState.closedState = false;
		if(FlxG.sound.music != null) FlxG.sound.music.fadeOut(0.3);
		if(FreeplayState.vocals != null)
		{
			FreeplayState.vocals.fadeOut(0.3);
			FreeplayState.vocals = null;
		}
		FlxG.camera.fade(FlxColor.BLACK, 0.5, false, FlxG.resetGame, false);
	}

	function openModsFolder()
	{
		#if desktop
		var modFolder:String = Paths.mods();
		if(!FileSystem.exists(modFolder))
		{
			trace('created missing mods folder');
			FileSystem.createDirectory(modFolder);
		}
		CoolUtil.openFolder(modFolder);
		#end
	}

	function updateSearch()
	{
		if(FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.TAB || FlxG.keys.justPressed.ENTER)
		{
			closeSearch();
			return;
		}

		var changed:Bool = false;
		if(FlxG.keys.justPressed.BACKSPACE)
		{
			if(searchQuery.length < 1)
			{
				closeSearch();
				return;
			}
			searchQuery = searchQuery.substr(0, searchQuery.length - 1);
			changed = true;
		}
		else
		{
			var typed:String = typedCharacter();
			if(typed != null && searchQuery.length < 24)
			{
				searchQuery += typed;
				changed = true;
			}
		}

		if(changed)
		{
			updateSearchText();
			jumpToSearchResult();
		}
	}

	// FlxKey values are plain ASCII codes for letters, digits and space
	function typedCharacter():String
	{
		var key:Int = FlxG.keys.firstJustPressed();
		if(key < 0) return null;

		if(key == 32) return ' ';
		if(key >= 65 && key <= 90) return String.fromCharCode(key).toLowerCase();
		if(key >= 48 && key <= 57) return String.fromCharCode(key);
		return null;
	}

	function updateSearchText()
	{
		searchText.text = 'SEARCH: ' + (searchQuery.length > 0 ? searchQuery : '_') + '   (ENTER or ESC to close)';
		searchText.visible = true;
		bottomText.visible = false;
	}

	function closeSearch()
	{
		searching = false;
		searchQuery = '';
		searchText.visible = false;
		bottomText.visible = true;

		for (mod in modsGroup.members) if(mod != null) mod.dimmed = false;
		updateItemPositions();
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
	}

	// Dims what doesn't match instead of hiding it, so drag reordering keeps working while searching
	function jumpToSearchResult()
	{
		var needle:String = searchQuery.toLowerCase();
		var firstMatch:Int = -1;

		for (i => mod in modsGroup.members)
		{
			if(mod == null) continue;

			var match:Bool = needle.length < 1
				|| mod.name.toLowerCase().indexOf(needle) >= 0
				|| mod.folder.toLowerCase().indexOf(needle) >= 0;

			mod.dimmed = !match;
			if(match && firstMatch < 0) firstMatch = i;
		}

		if(needle.length > 0 && firstMatch >= 0 && firstMatch != curSelectedMod)
		{
			curSelectedMod = firstMatch;
			updateModDisplayData();
		}
		else updateItemPositions();
	}

	function changeSelectedButton(add:Int = 0)
	{
		var max = buttons.length - 1;
		
		var button = getButton();
		button.ignoreCheck = button.onFocus = false;

		curSelectedButton += add;
		if(curSelectedButton < -2)
			curSelectedButton = -2;
		else if(curSelectedButton > max)
			curSelectedButton = max;

		var button = getButton();
		button.ignoreCheck = button.onFocus = true;

		var curMod:ModItem = modsGroup.members[curSelectedMod];
		if(curMod != null) curMod.selectBg.visible = false;
		if(curSelectedButton < 0)
		{
			bgButtons.color = FlxColor.BLACK;
			bgButtons.alpha = 0.2;
		}
		else
		{
			bgButtons.color = FlxColor.WHITE;
			bgButtons.alpha = 0.8;
		}

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	function getButton()
	{
		switch(curSelectedButton)
		{
			case -2: return buttonReload;
			case -1: return buttonEnableAll.enabled ? buttonEnableAll : buttonDisableAll;
		}

		if(modsList.all.length < 1) return buttonReload; //prevent possible crash from my irresponsibility
		return buttons[Std.int(Math.max(0, Math.min(buttons.length-1, curSelectedButton)))];
	}

	function changeSelectedMod(add:Int = 0, isMouseWheel:Bool = false)
	{
		var max = modsList.all.length - 1;
		if(max < 0) return;

		if(hoveringOnMods)
		{
			var button = getButton();
			button.ignoreCheck = button.onFocus = false;
		}

		var lastSelected = curSelectedMod;
		curSelectedMod += add;

		var limited:Bool = false;
		if(curSelectedMod < 0)
		{
			curSelectedMod = 0;
			limited = true;
		}
		else if(curSelectedMod > max)
		{
			curSelectedMod = max;
			limited = true;
		}
		
		if(!controls.mobileC && !isMouseWheel && limited && Math.abs(add) == 1)
		{
			if(add < 0) // pressed up on first mod
			{
				curSelectedMod = lastSelected;
				hoveringOnMods = false;
				curSelectedButton = -1;
				changeSelectedButton();
				return;
			}
			else // pressed down on last mod
			{
				curSelectedMod = lastSelected;
				hoveringOnMods = false;
				curSelectedButton = -2;
				changeSelectedButton();
				return;
			}
		}
		
		holdingMod = false;
		holdingElapsed = 0;
		gottaClickAgain = true;
		updateModDisplayData();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		
		if(hoveringOnMods)
		{
			var curMod:ModItem = modsGroup.members[curSelectedMod];
			if(curMod != null) curMod.selectBg.visible = true;
			bgButtons.color = FlxColor.BLACK;
			bgButtons.alpha = 0.2;
		}
	}

	var colorTween:FlxTween = null;
	function updateModDisplayData()
	{
		var curMod:ModItem = modsGroup.members[curSelectedMod];
		if(curMod == null) return;

		if(colorTween != null)
		{
			colorTween.cancel();
			colorTween.destroy();
		}
		colorTween = FlxTween.color(bg, 1, bg.color, curMod.bgColor, {onComplete: function(twn:FlxTween) colorTween = null});

		if(Math.abs(centerMod - curSelectedMod) > 2)
		{
			if(centerMod < curSelectedMod)
				centerMod = curSelectedMod - 2;
			else centerMod = curSelectedMod + 2;
		}
		updateItemPositions();

		icon.loadGraphic(curMod.icon.graphic, true, 150, 150);
		icon.antialiasing = curMod.icon.antialiasing;

		if(curMod.totalFrames > 0)
		{
			icon.animation.add("icon", [for (i in 0...curMod.totalFrames) i], curMod.iconFps);
			icon.animation.play("icon");
			icon.animation.curAnim.curFrame = curMod.icon.animation.curAnim.curFrame;
		}

		if(modName.scaleX != 0.8) modName.setScale(0.8);
		modName.text = curMod.name;
		var newScale = Math.min(620 / (modName.width / 0.8), 0.8);
		modName.setScale(newScale, Math.min(newScale * 1.35, 0.8));
		modName.y = modNameInitialY - (modName.height / 2);
		modRestartText.visible = curMod.mustRestart;
		modDesc.text = curMod.desc;
		modVersion.text = (curMod.version != null) ? 'v' + curMod.version : '';

		var issueLines:Array<String> = [];
		var fatal:Bool = false;
		for (issue in curMod.issues)
		{
			issueLines.push('- ' + issue.message);
			if(issue.fatal) fatal = true;
		}

		modIssues.visible = (issueLines.length > 0);
		modIssues.text = issueLines.join('\n');
		modIssues.color = fatal ? 0xFFFF6666 : 0xFFFFCC44;
		// Sits under the description, but never on top of the restart warning
		modIssues.y = Math.min(modDesc.y + modDesc.height + 14, modRestartText.y - modIssues.height - 8);

		// The base game entry can't be reordered, turned off or configured
		var isBase:Bool = (curMod.folder == Mods.BASE_GAME);
		for (button in moveButtons) button.enabled = !isBase && modCount > 1;
		toggleButton.enabled = !isBase;
		settingsButton.enabled = !isBase && (curMod.settings != null && curMod.settings.length > 0);

		for (button in buttons) if(button.focusChangeCallback != null) button.focusChangeCallback(button.onFocus);
	}

	var centerMod:Int = 2;
	function updateItemPositions()
	{
		var maxVisible = Math.max(4, centerMod + 2);
		var minVisible = Math.max(0, centerMod - 2);
		for (i => mod in modsGroup.members)
		{
			if(mod == null)
			{
				trace('Mod #$i is null, maybe it was ' + modsList.all[i]);
				continue;
			}

			mod.visible = (i >= minVisible && i <= maxVisible);
			mod.x = bgList.x + 5;
			mod.y = bgList.y + (86 * (i - centerMod + 2)) + 5;
			
			mod.alpha = 0.6;
			if(i == curSelectedMod) mod.alpha = 1;
			if(mod.dimmed) mod.alpha = 0.25; // filtered out by the search
			mod.selectBg.visible = (i == curSelectedMod && hoveringOnMods);
		}
	}

	var waitingToRestart:Bool = false;
	function moveModToPosition(?mod:String = null, position:Int = 0)
	{
		if(mod == null) mod = modsList.all[curSelectedMod];
		if(mod == Mods.BASE_GAME) return; // pinned to the top of the list

		// Index 0 belongs to the base game, so mods wrap around between 1 and the end
		if(position >= modsList.all.length) position = 1;
		else if(position < 1) position = modsList.all.length-1;

		trace('Moved mod $mod to position $position');
		var id:Int = modsList.all.indexOf(mod);
		if(position == id) return;

		var curMod:ModItem = modsGroup.members[id];
		if(curMod == null) return;

		if(curMod.mustRestart || modsGroup.members[position].mustRestart) waitingToRestart = true;

		modsGroup.remove(curMod, true);
		modsList.all.remove(mod);
		//if(position > id) position--;
		modsGroup.insert(position, curMod);
		modsList.all.insert(position, mod);

		curSelectedMod = position;
		updateModDisplayData();
		updateItemPositions();
		
		if(!hoveringOnMods)
		{
			var curMod:ModItem = modsGroup.members[curSelectedMod];
			if(curMod != null) curMod.selectBg.visible = false;
		}
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	function checkToggleButtons()
	{
		buttonEnableAll.visible = buttonEnableAll.enabled = buttonEnableAll.active = modsList.disabled.length > 0;
		buttonDisableAll.visible = buttonDisableAll.enabled = buttonDisableAll.active = !buttonEnableAll.visible;
	}

	function reload()
	{
		saveTxt();
		Mods.reload(); // pack.json files may have been edited while the game was running
		FlxG.autoPause = ClientPrefs.data.autoPause;
		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		var curMod:ModItem = modsGroup.members[curSelectedMod];
		MusicBeatState.switchState(new ModsMenuState(curMod != null ? curMod.folder : null));
	}
	
	function saveTxt()
	{
		// Writes modsList.txt and refreshes the cached list, load order and issues in one go
		Mods.saveModsList(modsList);
	}
}

class ModItem extends FlxSpriteGroup
{
	public var selectBg:FlxSprite;
	public var icon:FlxSprite;
	public var text:FlxText;
	public var totalFrames:Int = 0;

	// options
	public var name:String = 'Unknown Mod';
	public var desc:String = 'No description provided.';
	public var version:String = null;
	public var iconFps:Int = 10;
	public var bgColor:FlxColor = 0xFF665AFF;
	public var pack:Dynamic = null;
	public var folder:String = 'unknownMod';
	public var mustRestart:Bool = false;
	public var settings:Array<Dynamic> = null;
	public var issues:Array<ModIssue> = [];
	public var hasFatalIssues:Bool = false;
	public var dimmed:Bool = false;
	public var isBaseGame:Bool = false;

	public function new(folder:String)
	{
		super();

		this.folder = folder;
		this.isBaseGame = (folder == Mods.BASE_GAME);

		var meta:ModMetadata = null;
		if(!isBaseGame)
		{
			meta = Mods.getMetadata(folder);
			pack = meta.pack;

			issues = Mods.getIssues(folder);
			for (issue in issues) if(issue.fatal) { hasFatalIssues = true; break; }
		}

		var path:String = Paths.mods('$folder/data/settings.json');
		if(!isBaseGame && FileSystem.exists(path))
		{
			var data:String = File.getContent(path);
			try
			{
				//trace('trying to load settings: $folder');
				settings = tjson.TJSON.parse(data);
			}
			catch(e:Dynamic)
			{
				// Listed on the description panel instead of a blocking popup, next to the pack.json errors
				trace('ModsMenuState: couldn\'t parse "$path": $e');
				issues.push({
					mod: folder,
					kind: ModIssueKind.BROKEN_PACK,
					target: null,
					fatal: false,
					message: 'data/settings.json couldn\'t be read: $e'
				});
			}
		}

		selectBg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		selectBg.alpha = 0.8;
		selectBg.visible = false;
		add(selectBg);

		icon = new FlxSprite(5, 5);
		icon.antialiasing = ClientPrefs.data.antialiasing;
		add(icon);

		text = new FlxText(95, 38, 230, "", 16);
		text.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		text.borderSize = 2;
		text.y -= Std.int(text.height / 2);
		add(text);

		var isPixel = false;
		var bmp = isBaseGame ? null : Paths.cacheBitmap(Paths.mods('$folder/pack.png'));
		if(bmp == null && !isBaseGame)
		{
			bmp = Paths.cacheBitmap(Paths.mods('$folder/pack-pixel.png'));
			isPixel = true;
		}

		if(bmp != null)
		{
			icon.loadGraphic(bmp, true, 150, 150);
			if(isPixel) icon.antialiasing = false;
		}
		else
		{
			// Drop a 150x150 assets/shared/images/basegame.png in to give the base game its own icon.
			// ignoreMods so a mod can't hijack the entry that's supposed to represent the base game.
			var fallback:String = (isBaseGame && Paths.fileExists('images/basegame.png', IMAGE, true)) ? 'basegame' : 'unknownMod';
			icon.loadGraphic(Paths.image(fallback), true, 150, 150);
		}
		icon.scale.set(0.5, 0.5);
		icon.updateHitbox();

		if(isBaseGame)
		{
			this.name = 'Friday Night Funkin\'';
			this.desc = 'The base game, with everything that ships with the engine.\n\nMods you install show up under this entry. Pick one and press ENTER to play it instead.';
		}
		else
		{
			this.name = meta.name;
			this.desc = meta.description;
			this.version = meta.version;
			this.iconFps = meta.iconFramerate;
			this.mustRestart = meta.restart;
			if(meta.color != null)
			{
				this.bgColor = FlxColor.fromRGB(meta.color[0] != null ? meta.color[0] : 170,
												meta.color[1] != null ? meta.color[1] : 0,
												meta.color[2] != null ? meta.color[2] : 255);
			}
		}

		// Marks mods that won't work as they are, the Mods menu spells out why on the description panel
		text.text = hasFatalIssues ? '! ' + this.name : this.name;
		if(hasFatalIssues) text.color = 0xFFFFCC44;

		if(bmp != null)
		{
			totalFrames = Math.floor(bmp.width / 150) * Math.floor(bmp.height / 150);
			icon.animation.add("icon", [for (i in 0...totalFrames) i], iconFps);
			icon.animation.play("icon");
		}
		selectBg.scale.set(width + 5, height + 5);
		selectBg.updateHitbox();
	}
}

class MenuButton extends FlxSpriteGroup
{
	public var bg:FlxSprite;
	public var textOn:Alphabet;
	public var textOff:Alphabet;
	public var icon:FlxSprite;
	public var onClick:Void->Void = null;
	public var enabled(default, set):Bool = true;
	public function new(x:Float, y:Float, width:Int, height:Int, ?text:String = null, ?img:FlxGraphic = null, onClick:Void->Void = null, animWidth:Int = 0, animHeight:Int = 0)
	{
		super(x, y);
		
		bg = FlxSpriteUtil.drawRoundRect(new FlxSprite().makeGraphic(width, height, FlxColor.TRANSPARENT), 0, 0, width, height, 15, 15, FlxColor.WHITE);
		bg.color = FlxColor.BLACK;
		add(bg);

		if(text != null)
		{
			textOn = new Alphabet(0, 0, "", false);
			textOn.setScale(0.6);
			textOn.text = text;
			textOn.alpha = 0.6;
			textOn.visible = false;
			centerOnBg(textOn);
			textOn.y -= 30;
			add(textOn);
			
			textOff = new Alphabet(0, 0, "", true);
			textOff.setScale(0.52);
			textOff.text = text;
			textOff.alpha = 0.6;
			centerOnBg(textOff);
			add(textOff);
		}
		else if(img != null)
		{
			icon = new FlxSprite();
			if(animWidth > 0 || animHeight > 0) icon.loadGraphic(img, true, animWidth, animHeight);
			else icon.loadGraphic(img);
			centerOnBg(icon);
			add(icon);
		}

		this.onClick = onClick;
		setButtonVisibility(false);
	}

	public var focusChangeCallback:Bool->Void = null;
	public var onFocus(default, set):Bool = false;
	public var ignoreCheck:Bool = false;
	private var _needACheck:Bool = false;
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if(!enabled)
		{
			onFocus = false;
			return;
		}

		if (Controls.instance.mobileC) {
			if(!ignoreCheck)
				onFocus = TouchUtil.overlaps(this);

			if(onFocus && TouchUtil.justReleased)
				onFocus = false;

			if(onFocus && onClick != null && TouchUtil.justPressed)
				onClick();

			if(_needACheck) {
				_needACheck = false;
				setButtonVisibility(TouchUtil.overlaps(this));
			}
		} else {
			if(!ignoreCheck && !Controls.instance.controllerMode && FlxG.mouse.justMoved && FlxG.mouse.visible)
				onFocus = FlxG.mouse.overlaps(this);

			if(onFocus && onClick != null && FlxG.mouse.justPressed)
				onClick();

			if(_needACheck) {
				_needACheck = false;
				if(!Controls.instance.controllerMode)
					setButtonVisibility(FlxG.mouse.overlaps(this));
			}
		}
	}

	function set_onFocus(newValue:Bool)
	{
		var lastFocus:Bool = onFocus;
		onFocus = newValue;
		if(onFocus != lastFocus && enabled) setButtonVisibility(onFocus);
		return newValue;
	}

	function set_enabled(newValue:Bool)
	{
		enabled = newValue;
		setButtonVisibility(false);
		alpha = enabled ? 1 : 0.4;

		_needACheck = enabled;
		return newValue;
	}

	public function setButtonVisibility(focusVal:Bool)
	{
		alpha = 1;
		bg.color = focusVal ? FlxColor.WHITE : FlxColor.BLACK;
		bg.alpha = focusVal ? 0.8 : 0.6;

		var focusAlpha = focusVal ? 1 : 0.6;
		if(textOn != null && textOff != null)
		{
			textOn.alpha = textOff.alpha = focusAlpha;
			textOn.visible = focusVal;
			textOff.visible = !focusVal;
		}
		else if(icon != null)
		{
			icon.alpha = focusAlpha;
			icon.color = focusVal ? FlxColor.BLACK : FlxColor.WHITE;
		}

		if(!enabled) alpha = 0.4;
		if(focusChangeCallback != null) focusChangeCallback(focusVal);
	}

	public function centerOnBg(spr:FlxSprite)
	{
		spr.x = bg.width/2 - spr.width/2;
		spr.y = bg.height/2 - spr.height/2;
	}
}
