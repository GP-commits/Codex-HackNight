// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "game_formspec.h"

#include "gettext.h"
#include "nodemetadata.h"
#include "renderingengine.h"
#include "client.h"
#include "scripting_client.h"
#include "cpp_api/s_client_common.h"
#include "clientmap.h"
#include "gui/guiFormSpecMenu.h"
#include "gui/mainmenumanager.h"
#include "gui/touchcontrols.h"
#include "gui/touchscreeneditor.h"
#include "gui/guiPasswordChange.h"
#include "gui/guiPasswordChange.h"
#include "gui/guiOpenURL.h"
#include "gui/guiVolumeChange.h"
#include "localplayer.h"

/*
	Text input system
*/

struct TextDestNodeMetadata : public TextDest
{
	TextDestNodeMetadata(v3s16 p, Client *client)
	{
		m_p = p;
		m_client = client;
	}
	void gotText(const StringMap &fields)
	{
		m_client->sendNodemetaFields(m_p, "", fields);
	}

	v3s16 m_p;
	Client *m_client;
};

struct TextDestPlayerInventory : public TextDest
{
	TextDestPlayerInventory(Client *client)
	{
		m_client = client;
		m_formname.clear();
	}
	TextDestPlayerInventory(Client *client, const std::string &formname)
	{
		m_client = client;
		m_formname = formname;
	}
	void gotText(const StringMap &fields)
	{
		m_client->sendInventoryFields(m_formname, fields);
	}

	Client *m_client;
};

struct LocalScriptingFormspecHandler : public TextDest
{
	LocalScriptingFormspecHandler(const std::string &formname, ScriptApiClientCommon *script)
	{
		m_formname = formname;
		m_script = script;
	}

	void gotText(const StringMap &fields)
	{
		m_script->on_formspec_input(m_formname, fields);
	}

	ScriptApiClientCommon *m_script = nullptr;
};

struct HardcodedPauseFormspecHandler : public TextDest
{
	HardcodedPauseFormspecHandler()
	{
		m_formname = "MT_PAUSE_MENU";
	}

	void gotText(const StringMap &fields)
	{
		if (fields.find("btn_settings") != fields.end()) {
			g_gamecallback->openSettings();
			return;
		}

		if (fields.find("btn_sound") != fields.end()) {
			g_gamecallback->changeVolume();
			return;
		}

		if (fields.find("btn_exit_menu") != fields.end()) {
			g_gamecallback->disconnect();
			return;
		}

		if (fields.find("btn_exit_os") != fields.end()) {
			g_gamecallback->exitToOS();
#ifndef __ANDROID__
			RenderingEngine::get_raw_device()->closeDevice();
#endif
			return;
		}

		if (fields.find("btn_change_password") != fields.end()) {
			g_gamecallback->changePassword();
			return;
		}
	}
};

struct LegacyDeathFormspecHandler : public TextDest
{
	LegacyDeathFormspecHandler(Client *client)
	{
		m_formname = "MT_DEATH_SCREEN";
		m_client = client;
	}

	void gotText(const StringMap &fields)
	{
		if (fields.find("quit") != fields.end())
			m_client->sendRespawnLegacy();
	}

	Client *m_client = nullptr;
};

/* Form update callback */

class NodeMetadataFormSource: public IFormSource
{
public:
	NodeMetadataFormSource(ClientMap *map, v3s16 p):
		m_map(map),
		m_p(p)
	{
	}
	const std::string &getForm() const
	{
		static const std::string empty_string = "";
		NodeMetadata *meta = m_map->getNodeMetadata(m_p);

		if (!meta)
			return empty_string;

		return meta->getString("formspec");
	}

	virtual std::string resolveText(const std::string &str)
	{
		NodeMetadata *meta = m_map->getNodeMetadata(m_p);

		if (!meta)
			return str;

		return meta->resolveString(str);
	}

	ClientMap *m_map;
	v3s16 m_p;
};

class PlayerInventoryFormSource: public IFormSource
{
public:
	PlayerInventoryFormSource(Client *client):
		m_client(client)
	{
	}

	const std::string &getForm() const
	{
		LocalPlayer *player = m_client->getEnv().getLocalPlayer();

		if (!player->inventory_formspec_override.empty())
			return player->inventory_formspec_override;

		return player->inventory_formspec;
	}

	Client *m_client;
};


//// GameFormSpec

void GameFormSpec::init(Client *client, RenderingEngine *rendering_engine, InputHandler *input)
{
	m_client = client;
	m_rendering_engine = rendering_engine;
	m_input = input;
	m_pause_script = std::make_unique<PauseMenuScripting>(client);
	m_pause_script->loadBuiltin();

	// Make sure any remaining game callback requests are cleared out.
	*g_gamecallback = MainGameCallback();
}

void GameFormSpec::deleteFormspec()
{
	if (m_formspec) {
		m_formspec->drop();
		m_formspec = nullptr;
	}
}

void GameFormSpec::reset()
{
	if (m_formspec)
		m_formspec->quitMenu();
	deleteFormspec();
}

bool GameFormSpec::handleEmptyFormspec(const std::string &formspec, const std::string &formname)
{
	if (formspec.empty()) {
		GUIModalMenu *menu = g_menumgr.tryGetTopMenu();
		if (menu && (formname.empty() || formname == menu->getName())) {
			// `m_formspec` will be fixed up in `GameFormSpec::update()`
			menu->quitMenu();
		}
		return true;
	}
	return false;
}

void GameFormSpec::showFormSpec(const std::string &formspec, const std::string &formname)
{
	if (handleEmptyFormspec(formspec, formname))
		return;

	FormspecFormSource *fs_src =
		new FormspecFormSource(formspec);
	TextDestPlayerInventory *txt_dst =
		new TextDestPlayerInventory(m_client, formname);

	// Replace the currently open formspec
	GUIFormSpecMenu::create(m_formspec, m_client, m_rendering_engine->get_gui_env(),
		fs_src, txt_dst, m_client->getFormspecPrepend(),
		m_client->getSoundManager());
	m_formspec->setName(formname);
}

void GameFormSpec::showCSMFormSpec(const std::string &formspec, const std::string &formname)
{
	if (handleEmptyFormspec(formspec, formname))
		return;

	FormspecFormSource *fs_src = new FormspecFormSource(formspec);
	LocalScriptingFormspecHandler *txt_dst =
		new LocalScriptingFormspecHandler(formname, m_client->getScript());

	GUIFormSpecMenu::create(m_formspec, m_client, m_rendering_engine->get_gui_env(),
			fs_src, txt_dst, m_client->getFormspecPrepend(),
			m_client->getSoundManager());
	m_formspec->setName(formname);
}

void GameFormSpec::showPauseMenuFormSpec(const std::string &formspec, const std::string &formname)
{
	// The pause menu env is a trusted context like the mainmenu env and provides
	// the in-game settings formspec.
	// Neither CSM nor the server must be allowed to mess with it.

	// If we send updated formspec contents, we can either (1) recycle the old
	// GUIFormSpecMenu or (2) close the old and open a new one. This is option 2.
	(void)handleEmptyFormspec("", formname);
	if (formspec.empty())
		return;

	FormspecFormSource *fs_src = new FormspecFormSource(formspec);
	LocalScriptingFormspecHandler *txt_dst =
		new LocalScriptingFormspecHandler(formname, m_pause_script.get());

	GUIFormSpecMenu *fs = nullptr;
	GUIFormSpecMenu::create(fs, m_client, m_rendering_engine->get_gui_env(),
			// Ignore formspec prepend.
			fs_src, txt_dst, "",
			m_client->getSoundManager());

	fs->setName(formname);
	fs->doPause = true;
	fs->drop(); // 1 reference held by `g_menumgr`
}

void GameFormSpec::showNodeFormspec(const std::string &formspec, const v3s16 &nodepos)
{
	infostream << "Launching custom inventory view" << std::endl;

	InventoryLocation inventoryloc;
	inventoryloc.setNodeMeta(nodepos);

	NodeMetadataFormSource *fs_src = new NodeMetadataFormSource(
		&m_client->getEnv().getClientMap(), nodepos);
	TextDest *txt_dst = new TextDestNodeMetadata(nodepos, m_client);

	GUIFormSpecMenu::create(m_formspec, m_client, m_rendering_engine->get_gui_env(),
		fs_src, txt_dst, m_client->getFormspecPrepend(),
		m_client->getSoundManager());

	m_formspec->setFormSpec(formspec, inventoryloc);
}

void GameFormSpec::showPlayerInventory(const std::string *fs_override)
{
	/*
	 * Don't permit to open inventory is CAO or player doesn't exists.
	 * This prevent showing an empty inventory at player load
	 */

	LocalPlayer *player = m_client->getEnv().getLocalPlayer();
	if (!player || !player->getCAO())
		return;

	infostream << "Game: Launching inventory" << std::endl;

	auto fs_src = std::make_unique<PlayerInventoryFormSource>(m_client);

	InventoryLocation inventoryloc;
	inventoryloc.setCurrentPlayer();

	if (fs_override) {
		// Temporary overwrite for this specific formspec.
		player->inventory_formspec_override = *fs_override;
	} else {
		// Show the regular inventory formspec
		player->inventory_formspec_override.clear();
	}

	// If prevented by Client-Side Mods
	if (m_client->modsLoaded() && m_client->getScript()->on_inventory_open(m_client->getInventory(inventoryloc)))
		return;

	// Empty formspec -> do not show.
	if (fs_src->getForm().empty())
		return;

	TextDest *txt_dst = new TextDestPlayerInventory(m_client);

	GUIFormSpecMenu::create(m_formspec, m_client, m_rendering_engine->get_gui_env(),
		fs_src.get(), txt_dst, m_client->getFormspecPrepend(),
		m_client->getSoundManager());

	m_formspec->setFormSpec(fs_src->getForm(), inventoryloc);
	fs_src.release(); // owned by GUIFormSpecMenu
}

#define PAUSE_SIZE_TAG "size[10.8,6.3,true]" // Fixed size (ignored in touchscreen mode)
#define SIZE_TAG "size[11,5.5,true]" // Fixed size (ignored in touchscreen mode)

void GameFormSpec::showPauseMenu()
{
	std::string control_text;

	if (g_touchcontrols) {
		control_text = strgettext("Controls:\n"
			"No menu open:\n"
			"- slide finger: look around\n"
			"- tap: place/punch/use (default)\n"
			"- long tap: dig/use (default)\n"
			"Menu/inventory open:\n"
			"- double tap (outside):\n"
			" --> close\n"
			"- touch stack, touch slot:\n"
			" --> move stack\n"
			"- touch&drag, tap 2nd finger\n"
			" --> place single item to slot\n"
			);
	}

	auto simple_singleplayer_mode = m_client->m_simple_singleplayer_mode;

	float ypos = simple_singleplayer_mode ? 1.65f : 1.2f;
	std::ostringstream os;

	os << "formspec_version[4]" << PAUSE_SIZE_TAG
		<< "no_prepend[]"
		<< "bgcolor[#00000080;fullscreen]"
		<< "background[0,0;10.8,6.3;openclasscraft_pause_bg.png;true]"
		<< "box[0,0;10.8,6.3;#07131acc]"
		<< "box[0.22,0.22;10.36,5.86;#26333add]"
		<< "box[0.42,0.42;3.2,5.46;#111b20dd]"
		<< "box[3.85,0.42;6.52,5.46;#34434add]"
		<< "box[0.42,0.42;9.95,0.68;#6ea85bee]"
		<< "image[0.7,0.58;0.84,0.84;openclasscraft_pause_icon.png]"
		<< "style_type[label;textcolor=#ffffff]"
		<< "style_type[textarea;border=false;textcolor=#eef7ee]"
		<< "style_type[button;border=true;bgcolor=#55646a;textcolor=#ffffff;font_size=16]"
		<< "style_type[button:hovered;bgcolor=#6f8f6c;textcolor=#ffffff]"
		<< "style_type[button:pressed;bgcolor=#3e6a42;textcolor=#ffffff]"
		<< "style[btn_continue;bgcolor=#7bd982;textcolor=#0f2613;font=bold]"
		<< "style[btn_settings,btn_sound;bgcolor=#4c6470;textcolor=#ffffff]"
		<< "style[btn_exit_menu,btn_exit_os;bgcolor=#98545e;textcolor=#ffffff]"
		<< "label[1.72,0.7;OpenClassCraft]"
		<< "label[5.95,0.7;" << strgettext("Game Paused") << "]"
		<< "button_exit[5.25," << (ypos) << ";3.65,0.68;btn_continue;"
		// TRANSLATORS: Pause menu button, try to keep the translation short
		<< strgettext("Continue") << "]";
	ypos += 0.86f;

	if (!simple_singleplayer_mode) {
		os << "button[5.25," << (ypos) << ";3.65,0.68;btn_change_password;"
			// TRANSLATORS: Pause menu button, try to keep the translation short
			<< strgettext("Change Password") << "]";
		ypos += 0.86f;
	}

	os	<< "button[5.25," << (ypos) << ";3.65,0.68;btn_settings;"
		// TRANSLATORS: Try to keep the translation short
		<< strgettext("Settings") << "]";
	ypos += 0.86f;

#ifndef __ANDROID__
#if USE_SOUND
	os << "button[5.25," << (ypos) << ";3.65,0.68;btn_sound;"
		// TRANSLATORS: Pause menu button, try to keep the translation short
		<< strgettext("Sound Volume") << "]";
	ypos += 0.86f;
#endif
#endif

	os		<< "button_exit[5.25," << (ypos) << ";3.65,0.68;btn_exit_menu;"
		// TRANSLATORS: Pause menu button, try to keep the translation short
		<< strgettext("Exit to Menu") << "]";
	ypos += 0.86f;
	os		<< "button_exit[5.25," << (ypos) << ";3.65,0.68;btn_exit_os;"
		// TRANSLATORS: Pause menu button, try to keep the translation short (OS = Operating System)
		<< strgettext("Exit to OS")   << "]";
	if (!control_text.empty()) {
	os		<< "textarea[8.85,1.32;1.22,4.55;;" << control_text << ";]";
	}
	os		<< "textarea[0.75,1.62;2.55,3.92;;" << PROJECT_NAME_C " " VERSION_STRING "\n"
		<< "\n"
		<<  strgettext("Game info:") << "\n";
	const std::string &address = m_client->getAddressName();
	// TRANSLATORS: Game mode (server or singleplayer)
	os << strgettext("- Mode: ");
	if (!simple_singleplayer_mode) {
		if (address.empty())
			os << strgettext("Hosting server");
		else
			os << strgettext("Remote server");
	} else {
		os << strgettext("Singleplayer");
	}
	os << "\n";
	if (simple_singleplayer_mode || address.empty()) {
		static const std::string on = strgettext("On");
		static const std::string off = strgettext("Off");
		// Note: Status of enable_damage and creative_mode settings is intentionally
		// NOT shown here because the game might roll its own damage system and/or do
		// a per-player Creative Mode, in which case writing it here would mislead.
		bool damage = g_settings->getBool("enable_damage");
		const std::string &announced = g_settings->getBool("server_announce") ? on : off;
		if (!simple_singleplayer_mode) {
			if (damage) {
				const std::string &pvp = g_settings->getBool("enable_pvp") ? on : off;
				// TRANSLATORS: PvP = Player versus Player
				os << strgettext("- PvP: ") << pvp << "\n";
			}
			os << strgettext("- Public: ") << announced << "\n";
			std::string server_name = g_settings->get("server_name");
			str_formspec_escape(server_name);
			if (announced == on && !server_name.empty())
				os << strgettext("- Server Name: ") << server_name;

		}
	}
	os << ";]";

	/* Create menu */
	/* Note: FormspecFormSource and LocalFormspecHandler  *
	 * are deleted by guiFormSpecMenu                     */
	FormspecFormSource *fs_src = new FormspecFormSource(os.str());
	HardcodedPauseFormspecHandler *txt_dst = new HardcodedPauseFormspecHandler();

	GUIFormSpecMenu::create(m_formspec, m_client, m_rendering_engine->get_gui_env(),
			fs_src, txt_dst, m_client->getFormspecPrepend(),
			m_client->getSoundManager());
	m_formspec->setFocus("btn_continue");
	// game will be paused in next step, if in singleplayer (see Game::m_is_paused)
	m_formspec->doPause = true;
}

void GameFormSpec::showDeathFormspecLegacy()
{
	static std::string formspec_str =
		std::string("formspec_version[1]") +
		SIZE_TAG
		"bgcolor[#320000b4;true]"
		"label[4.85,1.35;" + gettext("You died") + "]"
		"button_exit[4,3;3,0.5;btn_respawn;" + gettext("Respawn") + "]"
		;

	/* Create menu */
	/* Note: FormspecFormSource and LocalFormspecHandler  *
	 * are deleted by guiFormSpecMenu                     */
	FormspecFormSource *fs_src = new FormspecFormSource(formspec_str);
	LegacyDeathFormspecHandler *txt_dst = new LegacyDeathFormspecHandler(m_client);

	GUIFormSpecMenu::create(m_formspec, m_client, m_rendering_engine->get_gui_env(),
		fs_src, txt_dst, m_client->getFormspecPrepend(),
		m_client->getSoundManager());
	m_formspec->setFocus("btn_respawn");
}

void GameFormSpec::update()
{
	/*
	   make sure menu is on top
	   1. Delete formspec menu reference if menu was removed
	   2. Else, make sure formspec menu is on top
	*/
	if (!m_formspec)
		return;

	if (m_formspec->getReferenceCount() == 1) {
		// See GUIFormSpecMenu::create what refcnt = 1 means
		this->deleteFormspec();
		return;
	}

	auto &loc = m_formspec->getFormspecLocation();
	if (loc.type == InventoryLocation::NODEMETA) {
		NodeMetadata *meta = m_client->getEnv().getClientMap().getNodeMetadata(loc.p);
		if (!meta || meta->getString("formspec").empty()) {
			m_formspec->quitMenu();
			return;
		}
	}

	if (isMenuActive())
		guiroot->bringToFront(m_formspec);
}

void GameFormSpec::disableDebugView()
{
	if (m_formspec) {
		m_formspec->setDebugView(false);
	}
}

/* returns false if game should exit, otherwise true
 */
bool GameFormSpec::handleCallbacks()
{
	auto texture_src = m_client->getTextureSource();

	if (g_gamecallback->disconnect_requested) {
		g_gamecallback->disconnect_requested = false;
		return false;
	}

	if (g_gamecallback->settings_requested) {
		m_pause_script->open_settings();
		g_gamecallback->settings_requested = false;
	}

	if (g_gamecallback->changepassword_requested) {
		(void)make_irr<GUIPasswordChange>(guienv, guiroot, -1,
				       &g_menumgr, m_client, texture_src);
		g_gamecallback->changepassword_requested = false;
	}

	if (g_gamecallback->changevolume_requested) {
		(void)make_irr<GUIVolumeChange>(guienv, guiroot, -1,
				     &g_menumgr, texture_src);
		g_gamecallback->changevolume_requested = false;
	}

	if (g_gamecallback->touchscreenlayout_requested) {
		(new GUITouchscreenLayout(guienv, guiroot, -1,
				     &g_menumgr, texture_src))->drop();
		g_gamecallback->touchscreenlayout_requested = false;
	}

	if (!g_gamecallback->show_open_url_dialog.empty()) {
		(void)make_irr<GUIOpenURLMenu>(guienv, guiroot, -1,
				 &g_menumgr, texture_src, g_gamecallback->show_open_url_dialog);
		g_gamecallback->show_open_url_dialog.clear();
	}

	return true;
}

#ifdef __ANDROID__
bool GameFormSpec::handleAndroidUIInput()
{
	// FIXME: m_formspec and this value are not in sync at all times.
	GUIModalMenu *menu = g_menumgr.tryGetTopMenu();
	if (menu) {
		menu->getAndroidUIInput();
		return true;
	}
	return false;
}
#endif
