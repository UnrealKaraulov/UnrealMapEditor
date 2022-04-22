#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <reapi>
#include <json>
#include <fakemeta>

#define PLUGIN "Unreal Map Editor"
#define VERSION "1.6"
#define AUTHOR "karaulov"

new UNREAL_MDLS_DIRECTORY[] = "models/umedit";
new UNREAL_MDLS_CUSTOM_CLASSNAME[] = "unreal_mdl";

new UNREAL_MDL_ACCESS_LEVEL = ADMIN_BAN;
new UNREAL_MDL_MAGIC_NUMBER = 0xBADC0DE;
new UNREAL_MDL_MAX_MENUS = 11;

#define TASK_THINK 10000
#define TASK_CREATE_ADS 1000
#define TASK_UNSTUCK 2000
#define TASK_SET_VELOCITY 4000
#define TASK_RESET_VELOCITY 5000

#define MAX_RES_PATH 64

new JSON: g_jAdsList = Invalid_JSON;
new g_sAdsPath[512];
new g_iPrecachedModels = 0;

new Float: g_fRoundStartTime = 0.0;

new g_iPlayerTeams[33] = { 0, ... };
new g_iPlayerSelectID[33] = { 0, ... };

new g_sMapName[33];

new g_iRoundID = 0;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	//https://www.gametracker.com/search/?search_by=server_variable&search_by2=unreal_ads&query=&loc=_all&sort=&order=
	//https://gs-monitor.com/?searchType=2&variableName=unreal_ads&variableValue=&submit=&mode=
	register_cvar("unreal_ads", VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Pre");
	register_forward(FM_AddToFullPack, "AddToFullPack_Post", ._post = true);
	RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", true);

	set_task_ex(1.0, "cache_player_teams", .flags = SetTask_Repeat);

	register_clcmd("say /adcreate", "MENU_CREATEAD")
	register_clcmd("unreal_mdl_create", "MENU_CREATEAD")

	register_clcmd("say /adedit", "MENU_AD_MENU_SELECT")
	register_clcmd("unreal_mdl_edit", "MENU_AD_MENU_SELECT")

	update_all_ads(0);
}

public CSGameRules_RestartRound_Pre()
{
	g_iRoundID++;
	update_all_ads(0);
}

public AddToFullPack_Post(const handle, const e, const ent, const host, const hostflags, const bool: player, const pSet)
{
	if (!player && pev_valid(ent))
	{
		new iEntTeam = get_entvar(ent, var_iuser2) - UNREAL_MDL_MAGIC_NUMBER;
		if (iEntTeam >= 1 && iEntTeam <= 4)
		{
			new effects = get_es(handle, ES_Effects);
			if (g_iPlayerTeams[host] != iEntTeam && !(effects & EF_NODRAW))
			{
				set_es(handle, ES_Effects, effects + EF_NODRAW);
			}
		}
	}
}

public CBasePlayer_Spawn_Post(const id)
{
	if (is_user_alive(id))
	{
		unstuckplayer(id);
	}
}

new g_iSelectedAd[33] = { 0, ... };

new g_iSelectedMenu[33] = { 0, ... };

public get_ads_count_map()
{
	if (get_ads_count() == 0)
		return 0;
	new startid = 0;
	new endid = get_ads_count();
	new ad_mapname[64];
	new cnt = 0;
	while (startid < endid)
	{
		get_ad_map(startid, ad_mapname, charsmax(ad_mapname));
		if (equal(ad_mapname, g_sMapName))
		{
			cnt++;
		}

		startid++;
	}

	return cnt;
}

public search_next_ad(id)
{
	g_iSelectedAd[id]++;
	if (g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	while (get_ad_precache(g_iSelectedAd[id]) < 0)
	{
		g_iSelectedAd[id]++;
		if (g_iSelectedAd[id] >= get_ads_count())
		{
			g_iSelectedAd[id] = 0;
			break;
		}
	}

	new tmpMap[64];
	get_ad_map(g_iSelectedAd[id], tmpMap, charsmax(tmpMap));
	while (!equal(tmpMap, g_sMapName))
	{
		g_iSelectedAd[id]++;
		if (g_iSelectedAd[id] >= get_ads_count())
		{
			g_iSelectedAd[id] = 0;
			break;
		}

		get_ad_map(g_iSelectedAd[id], tmpMap, charsmax(tmpMap));
	}
}

public MENU_DISABLEAD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[MODEL STATUS]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_DISABLEAD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\wСтатус:[\r%s\w]", get_ad_disabled(g_iSelectedAd[id]) > 0 ? "ОТКЛЮЧЕНО" : "ВКЛЮЧЕНО");
	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "Переместиться к модели", "2")
	menu_additem(vmenu, "Переместить модель сюда", "3")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rDISABLE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_DISABLEAD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				set_ad_disabled(g_iSelectedAd[id], get_ad_disabled(g_iSelectedAd[id]) == 0 ? 1 : 0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				new Float: vOrigin[3];
				get_ad_origin(g_iSelectedAd[id], vOrigin);
				set_entvar(id, var_origin, vOrigin);
				MENU_AD_MENU_SELECT(id);
				unstuckplayer(id);
			}

		case 3:
			{
				new Float: vOrigin[3];
				get_entvar(id, var_origin, vOrigin);
				set_ad_origin(g_iSelectedAd[id], vOrigin);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu);
	return PLUGIN_HANDLED;
}

public MENU_TEAMVISIBLE(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[MODEL VISIBILITY]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_TEAMVISIBLE_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%s\w]", "Команда:",
		get_ad_team(g_iSelectedAd[id]) == 0 ? "ЛЮБАЯ" :
		get_ad_team(g_iSelectedAd[id]) == 1 ? "ТЕРРОР" :
		get_ad_team(g_iSelectedAd[id]) == 2 ? "КТ" : "ЗРИТЕЛИ");

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rTEAM\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_TEAMVISIBLE_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				new teamid = get_ad_team(g_iSelectedAd[id]);
				teamid++;
				if (teamid >= 4)
					teamid = 0;
				set_ad_team(g_iSelectedAd[id], teamid);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

new g_iSelectedCoord[33] = { 0, ... };

public MENU_MOVEAD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[MOVE MODEL]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_MOVEAD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%s\w]", "Координата:",
		g_iSelectedCoord[id] == 0 ? "X" :
		g_iSelectedCoord[id] == 1 ? "Y" : "Z");

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wДвигать[\r+1\w]", "2")
	menu_additem(vmenu, "\wДвигать[\r+10\w]", "3")

	menu_additem(vmenu, "\wДвигать[\r-1\w]", "4")
	menu_additem(vmenu, "\wДвигать[\r-10\w]", "5")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rMOVE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_MOVEAD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				g_iSelectedCoord[id]++;
				if (g_iSelectedCoord[id] > 2)
					g_iSelectedCoord[id] = 0;
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				new Float: vOrigin[3];
				get_ad_origin(g_iSelectedAd[id], vOrigin);
				vOrigin[g_iSelectedCoord[id]] += 1;
				set_ad_origin(g_iSelectedAd[id], vOrigin);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				new Float: vOrigin[3];
				get_ad_origin(g_iSelectedAd[id], vOrigin);
				vOrigin[g_iSelectedCoord[id]] += 10;
				set_ad_origin(g_iSelectedAd[id], vOrigin);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				new Float: vOrigin[3];
				get_ad_origin(g_iSelectedAd[id], vOrigin);
				vOrigin[g_iSelectedCoord[id]] -= 1;
				set_ad_origin(g_iSelectedAd[id], vOrigin);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				new Float: vOrigin[3];
				get_ad_origin(g_iSelectedAd[id], vOrigin);
				vOrigin[g_iSelectedCoord[id]] -= 10;
				set_ad_origin(g_iSelectedAd[id], vOrigin);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_FRAMERATEAD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[MODEL FPS]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_FRAMERATEAD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%.2f\w]", "FPS:", get_ad_framerate(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wУвеличить[\r+0.5\w]", "2")

	menu_additem(vmenu, "\wУменьшить[\r-0.5\w]", "3")

	menu_additem(vmenu, "\wУвеличить[\r+1\w]", "4")

	menu_additem(vmenu, "\wУменьшить[\r-1\w]", "5")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%.0f\w]", "FIRST FRAME:", get_ad_firstframe(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "6")

	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rFPS\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_FRAMERATEAD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				set_ad_framerate(g_iSelectedAd[id], get_ad_framerate(g_iSelectedAd[id]) + 0.5);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				set_ad_framerate(g_iSelectedAd[id], get_ad_framerate(g_iSelectedAd[id]) - 0.5);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				set_ad_framerate(g_iSelectedAd[id], get_ad_framerate(g_iSelectedAd[id]) + 1.0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				set_ad_framerate(g_iSelectedAd[id], get_ad_framerate(g_iSelectedAd[id]) - 1.0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 6:
			{
				new Float: fFrameNextID = get_ad_firstframe(g_iSelectedAd[id]) + 1.0;
				set_ad_firstframe(g_iSelectedAd[id], fFrameNextID);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

new bool: g_bIsShowTimePresents[33] = { false, ... };

public MENU_DELAY_START_END_AD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[\yMODEL START/END TIME\r]^n%d=\r[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_DELAY_START_END_AD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\y%s\r] =[\r%i\w]", g_bIsShowTimePresents[id] ? "START TIME" : "END TIME",
		g_bIsShowTimePresents[id] ? get_ad_starttime(g_iSelectedAd[id]) : get_ad_lifetime(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wУвеличить[\r+1\w]", "2")

	menu_additem(vmenu, "\wУменьшить[\r-1\w]", "3")

	menu_additem(vmenu, "\wУвеличить[\r+10\w]", "4")

	menu_additem(vmenu, "\wУменьшить[\r-10\w]", "5")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rTIMELIFE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_DELAY_START_END_AD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				g_bIsShowTimePresents[id] = !g_bIsShowTimePresents[id];
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starttime(g_iSelectedAd[id], get_ad_starttime(g_iSelectedAd[id]) + 1);
				else
					set_ad_lifetime(g_iSelectedAd[id], get_ad_lifetime(g_iSelectedAd[id]) + 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starttime(g_iSelectedAd[id], get_ad_starttime(g_iSelectedAd[id]) - 1);
				else
					set_ad_lifetime(g_iSelectedAd[id], get_ad_lifetime(g_iSelectedAd[id]) - 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starttime(g_iSelectedAd[id], get_ad_starttime(g_iSelectedAd[id]) + 10);
				else
					set_ad_lifetime(g_iSelectedAd[id], get_ad_lifetime(g_iSelectedAd[id]) + 10);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starttime(g_iSelectedAd[id], get_ad_starttime(g_iSelectedAd[id]) - 10);
				else
					set_ad_lifetime(g_iSelectedAd[id], get_ad_lifetime(g_iSelectedAd[id]) - 10);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_DELAY_ROUND_START_END_AD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[\yMODEL START/END ROUND\r]^n%d=\r[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_DELAY_ROUND_START_END_AD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\y%s\r] =[\r%i\w]", g_bIsShowTimePresents[id] ? "START ROUND" : "END ROUND",
		g_bIsShowTimePresents[id] ? get_ad_starround(g_iSelectedAd[id]) : get_ad_endround(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wУвеличить[\r+1\w]", "2")

	menu_additem(vmenu, "\wУменьшить[\r-1\w]", "3")

	menu_additem(vmenu, "\wУвеличить[\r+10\w]", "4")

	menu_additem(vmenu, "\wУменьшить[\r-10\w]", "5")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rTIMELIFE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_DELAY_ROUND_START_END_AD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				g_bIsShowTimePresents[id] = !g_bIsShowTimePresents[id];
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starround(g_iSelectedAd[id], get_ad_starround(g_iSelectedAd[id]) + 1);
				else
					set_ad_endround(g_iSelectedAd[id], get_ad_endround(g_iSelectedAd[id]) + 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starround(g_iSelectedAd[id], get_ad_starround(g_iSelectedAd[id]) - 1);
				else
					set_ad_endround(g_iSelectedAd[id], get_ad_endround(g_iSelectedAd[id]) - 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starround(g_iSelectedAd[id], get_ad_starround(g_iSelectedAd[id]) + 10);
				else
					set_ad_endround(g_iSelectedAd[id], get_ad_endround(g_iSelectedAd[id]) + 10);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_starround(g_iSelectedAd[id], get_ad_starround(g_iSelectedAd[id]) - 10);
				else
					set_ad_endround(g_iSelectedAd[id], get_ad_endround(g_iSelectedAd[id]) - 10);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}


public MENU_DELAY_ONLINE_AD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[\yMODEL ONLINE\r]^n%d=\r[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_DELAY_ONLINE_AD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\y%s\r] =[\r%i\w]", g_bIsShowTimePresents[id] ? "MIN ONLINE" : "MAX ONLINE",
		g_bIsShowTimePresents[id] ? get_ad_minonline(g_iSelectedAd[id]) : get_ad_maxonline(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wУвеличить[\r+1\w]", "2")

	menu_additem(vmenu, "\wУменьшить[\r-1\w]", "3")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rONLINE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_DELAY_ONLINE_AD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				g_bIsShowTimePresents[id] = !g_bIsShowTimePresents[id];
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_minonline(g_iSelectedAd[id], get_ad_minonline(g_iSelectedAd[id]) + 1);
				else
					set_ad_maxonline(g_iSelectedAd[id], get_ad_maxonline(g_iSelectedAd[id]) + 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				if (g_bIsShowTimePresents[id])
					set_ad_minonline(g_iSelectedAd[id], get_ad_minonline(g_iSelectedAd[id]) - 1);
				else
					set_ad_maxonline(g_iSelectedAd[id], get_ad_maxonline(g_iSelectedAd[id]) - 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_SEQNUMAD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodeltype[64];
	get_ad_type(g_iSelectedAd[id], tmpmodeltype, charsmax(tmpmodeltype));
	if (!equal(tmpmodeltype, "MODEL"))
	{
		g_iSelectedMenu[id]++;
		if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
		{
			g_iSelectedMenu[id] = 0;
		}

		MENU_AD_MENU_SELECT(id);
		return;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[MODEL SEQUENCE]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_SEQNUMAD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%i\w]", "SEQUENCE NUM:", get_ad_sequence(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wСледующая[\r+1\w]", "2")
	menu_additem(vmenu, "\wПредыдущая[\r-1\w]", "3")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rSEQ\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_SEQNUMAD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				set_ad_sequence(g_iSelectedAd[id], get_ad_sequence(g_iSelectedAd[id]) + 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				set_ad_sequence(g_iSelectedAd[id], get_ad_sequence(g_iSelectedAd[id]) - 1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_ANGLEAD(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[ROTATE MODEL]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_ANGLEAD_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%s\w]", "Координата:",
		g_iSelectedCoord[id] == 0 ? "X" :
		g_iSelectedCoord[id] == 1 ? "Y" : "Z");

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wВращать[\r+1\w]", "2")
	menu_additem(vmenu, "\wВращать[\r+10\w]", "3")

	menu_additem(vmenu, "\wВращать[\r-1\w]", "4")
	menu_additem(vmenu, "\wВращать[\r-10\w]", "5")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rANGLE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_ANGLEAD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				g_iSelectedCoord[id]++;
				if (g_iSelectedCoord[id] > 2)
					g_iSelectedCoord[id] = 0;
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				new Float: vAngles[3];
				get_ad_angles(g_iSelectedAd[id], vAngles);
				vAngles[g_iSelectedCoord[id]] += 1;
				set_ad_angles(g_iSelectedAd[id], vAngles);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				new Float: vAngles[3];
				get_ad_angles(g_iSelectedAd[id], vAngles);
				vAngles[g_iSelectedCoord[id]] += 10;
				set_ad_angles(g_iSelectedAd[id], vAngles);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				new Float: vAngles[3];
				get_ad_angles(g_iSelectedAd[id], vAngles);
				vAngles[g_iSelectedCoord[id]] -= 1;
				set_ad_angles(g_iSelectedAd[id], vAngles);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				new Float: vAngles[3];
				get_ad_angles(g_iSelectedAd[id], vAngles);
				vAngles[g_iSelectedCoord[id]] -= 10;
				set_ad_angles(g_iSelectedAd[id], vAngles);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_ROTATEAD_SPEED(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new sModelType[MAX_RES_PATH];
	get_ad_type(g_iSelectedAd[id], sModelType, charsmax(sModelType));

	/*if (containi(sModelType,"bsp") != -1)
	{
		g_iSelectedMenu[id]++;
		if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
		{
			g_iSelectedMenu[id] = 0;
		}

		MENU_AD_MENU_SELECT(id);
		return;
	}*/

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[ROTATE ALWAYS]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_ROTATEAD_SPEED_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	new iSelectedRotateDir = get_ad_rotatedir(g_iSelectedAd[id]);

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%s\w] \wSPEED:[\r%.2f\w]", "Координата:",
		iSelectedRotateDir == 0 ? "DISABLED" :
		iSelectedRotateDir == 1 ? "X" :
		iSelectedRotateDir == 2 ? "Y" :
		iSelectedRotateDir == 3 ? "Z" :
		iSelectedRotateDir == 4 ? "XY" :
		iSelectedRotateDir == 5 ? "XZ" :
		iSelectedRotateDir == 6 ? "YZ" : "XYZ", get_ad_rotate_speed(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	menu_additem(vmenu, "\wВращать[\r+0.1\w]", "2")
	menu_additem(vmenu, "\wВращать[\r+1\w]", "3")

	menu_additem(vmenu, "\wВращать[\r-0.1\w]", "4")
	menu_additem(vmenu, "\wВращать[\r-1\w]", "5")

	menu_addblank(vmenu, 1);
	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rROTATE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_ROTATEAD_SPEED_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 0:
			{
				MENU_AD_MENU_SELECT(id);
			}

		case 1:
			{
				new iSelectedRotateDir = get_ad_rotatedir(g_iSelectedAd[id]) + 1;
				if (iSelectedRotateDir > 7)
					iSelectedRotateDir = 0;
				set_ad_rotatedir(g_iSelectedAd[id], iSelectedRotateDir);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				set_ad_rotate_speed(g_iSelectedAd[id], get_ad_rotate_speed(g_iSelectedAd[id]) + 0.1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				set_ad_rotate_speed(g_iSelectedAd[id], get_ad_rotate_speed(g_iSelectedAd[id]) + 1.0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				set_ad_rotate_speed(g_iSelectedAd[id], get_ad_rotate_speed(g_iSelectedAd[id]) - 0.1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				set_ad_rotate_speed(g_iSelectedAd[id], get_ad_rotate_speed(g_iSelectedAd[id]) - 1.0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_MOVEAD_SPEED(id)
{
	if (get_ads_count_map() == 0)
	{
		client_print_color(id, print_team_red, "НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return;
	}

	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}

	new sModelType[MAX_RES_PATH];
	get_ad_type(g_iSelectedAd[id], sModelType, charsmax(sModelType));

	/*if (containi(sModelType,"bsp") != -1)
	{
		g_iSelectedMenu[id]++;
		if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
		{
			g_iSelectedMenu[id] = 0;
		}

		MENU_AD_MENU_SELECT(id);
		return;
	}*/

	new tmpmodelpath[MAX_RES_PATH];
	get_ad_model(g_iSelectedAd[id], tmpmodelpath, charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[MOVE ALWAYS]^n%d=[\w%s\r]", g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_MOVEAD_SPEED_HANDLER")

	menu_additem(vmenu, "\wСледующее меню", "102")
	menu_additem(vmenu, "\yСледующая модель", "100")

	new iSelectedMoveDir = get_ad_movedir(g_iSelectedAd[id]);

	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%s\w] \wSPEED:[\r%.2f\w]", "Координата:",
		iSelectedMoveDir == 0 ? "DISABLED" :
		iSelectedMoveDir == 1 ? "X" :
		iSelectedMoveDir == 2 ? "Y" :
		iSelectedMoveDir == 3 ? "Z" :
		iSelectedMoveDir == 4 ? "XY" :
		iSelectedMoveDir == 5 ? "XZ" :
		iSelectedMoveDir == 6 ? "YZ" : "XYZ", get_ad_move_speed(g_iSelectedAd[id]));

	menu_additem(vmenu, tmpmenuitem, "1")

	iSelectedMoveDir = get_ad_reversemovedir(g_iSelectedAd[id]);
	formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w%s[\r%s\w]", "Обратная координата:",
		iSelectedMoveDir == 0 ? "DISABLED" :
		iSelectedMoveDir == 1 ? "X" :
		iSelectedMoveDir == 2 ? "Y" :
		iSelectedMoveDir == 3 ? "Z" :
		iSelectedMoveDir == 4 ? "XY" :
		iSelectedMoveDir == 5 ? "XZ" :
		iSelectedMoveDir == 6 ? "YZ" : "XYZ");

	menu_additem(vmenu, tmpmenuitem, "6")

	menu_additem(vmenu, "\wСкорость[\r+0.1\w]", "2")
	menu_additem(vmenu, "\wСкорость[\r+1\w]", "3")

	menu_additem(vmenu, "\wСкорость[\r-0.1\w]", "4")
	menu_additem(vmenu, "\wСкорость[\r-1\w]", "5")

	menu_addblank(vmenu, 1);

	menu_additem(vmenu, "Выход", "EXIT")

	menu_setprop(vmenu, MPROP_PERPAGE, 0);
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rMOVEMENT\w] меню")
	menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

	menu_display(id, vmenu, 0)
}

public MENU_MOVEAD_SPEED_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 0:
			{
				MENU_AD_MENU_SELECT(id);
			}

		case 1:
			{
				new iSelectedMoveDir = get_ad_movedir(g_iSelectedAd[id]) + 1;
				if (iSelectedMoveDir > 7)
					iSelectedMoveDir = 0;
				set_ad_movedir(g_iSelectedAd[id], iSelectedMoveDir);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 6:
			{
				new iSelectedMoveDir = get_ad_reversemovedir(g_iSelectedAd[id]) + 1;
				if (iSelectedMoveDir > 7)
					iSelectedMoveDir = 0;
				set_ad_reversemovedir(g_iSelectedAd[id], iSelectedMoveDir);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 2:
			{
				set_ad_move_speed(g_iSelectedAd[id], get_ad_move_speed(g_iSelectedAd[id]) + 0.1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 3:
			{
				set_ad_move_speed(g_iSelectedAd[id], get_ad_move_speed(g_iSelectedAd[id]) + 1.0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 4:
			{
				set_ad_move_speed(g_iSelectedAd[id], get_ad_move_speed(g_iSelectedAd[id]) - 0.1);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 5:
			{
				set_ad_move_speed(g_iSelectedAd[id], get_ad_move_speed(g_iSelectedAd[id]) - 1.0);
				update_all_ads(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 100:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 101:
			{
				search_next_ad(id);
				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_AD_MENU_SELECT(id)
{
	if (get_user_flags(id) &UNREAL_MDL_ACCESS_LEVEL)
	{
		if (g_iSelectedMenu[id] == 0)
		{
			MENU_DISABLEAD(id);
		}
		else if (g_iSelectedMenu[id] == 1)
		{
			MENU_FRAMERATEAD(id);
		}
		else if (g_iSelectedMenu[id] == 2)
		{
			MENU_SEQNUMAD(id);
		}
		else if (g_iSelectedMenu[id] == 3)
		{
			MENU_TEAMVISIBLE(id);
		}
		else if (g_iSelectedMenu[id] == 4)
		{
			MENU_MOVEAD(id);
		}
		else if (g_iSelectedMenu[id] == 5)
		{
			MENU_MOVEAD_SPEED(id);
		}
		else if (g_iSelectedMenu[id] == 6)
		{
			MENU_ANGLEAD(id);
		}
		else if (g_iSelectedMenu[id] == 7)
		{
			MENU_ROTATEAD_SPEED(id);
		}
		else if (g_iSelectedMenu[id] == 8)
		{
			MENU_DELAY_ONLINE_AD(id);
		}
		else if (g_iSelectedMenu[id] == 9)
		{
			MENU_DELAY_START_END_AD(id);
		}
		else
		{
			MENU_DELAY_ROUND_START_END_AD(id);
		}
	}
}

public CREATE_NEW_AD(id, adtype[])
{
	new tmpmodelpath[MAX_RES_PATH];
	precache_get_model(g_iPlayerSelectID[id], tmpmodelpath, charsmax(tmpmodelpath));
	new ads = get_ads_count();
	new Float: vOrigin[3];
	get_entvar(id, var_origin, vOrigin);
	g_iSelectedAd[id] = get_ads_count();
	set_ads_count(get_ads_count() + 1);
	set_ad_model(ads, tmpmodelpath);
	set_ad_type(ads, adtype);
	set_ad_origin(ads, vOrigin);
	set_ad_angles(ads, Float: {0.0, 0.0, 0.0 });
	set_ad_disabled(ads, 0);
	set_ad_starttime(ads, 0);
	set_ad_lifetime(ads, 0);
	set_ad_map(ads, g_sMapName);
	set_ad_precache(ads, add_precache_model(tmpmodelpath));
	set_ad_rotate_speed(ads, 0.0);
	set_ad_rotatedir(ads, 0);
	set_ad_move_speed(ads, 0.0);
	set_ad_movedir(ads, 0);
	set_ad_reversemovedir(ads, 0);
	set_ad_team(ads, 0);
	set_ad_framerate(ads, 1.0);
	set_ad_sequence(ads, 0);
	set_ad_starround(ads, 0);
	set_ad_endround(ads, 0);
	set_ad_firstframe(ads, 0.0);
	update_all_ads(id);
}

public MENU_CREATEAD(id)
{
	if (get_user_flags(id) &UNREAL_MDL_ACCESS_LEVEL)
	{
		if (g_iPrecachedModels == 0)
		{
			client_print_color(id, print_team_red, "НЕТ ДОСТУПНЫХ МОДЕЛЕЙ");
			return;
		}

		if (g_iPlayerSelectID[id] < 0 || g_iPlayerSelectID[id] >= g_iPrecachedModels)
		{
			g_iPlayerSelectID[id] = 0;
		}

		new tmpmodelpath[MAX_RES_PATH];
		precache_get_model(g_iPlayerSelectID[id], tmpmodelpath, charsmax(tmpmodelpath));

		new tmpmenuitem[256];
		formatex(tmpmenuitem, charsmax(tmpmenuitem), "\r[CREATE MODEL]^n[\w%s\r]", tmpmodelpath);

		new vmenu = menu_create(tmpmenuitem, "MENU_CREATEAD_HANDLER")
		menu_additem(vmenu, "\wСледующее меню", "101")
		menu_additem(vmenu, "\yСледующая модель", "102")

		formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\r%s\w]", "Создать SPRITE");
		menu_additem(vmenu, tmpmenuitem, "1")
		formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\r%s\w]", "Создать MODEL");
		menu_additem(vmenu, tmpmenuitem, "2")
		formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\r%s\w]", "Создать MODEL_SOLID");
		menu_additem(vmenu, tmpmenuitem, "3")
		if (containi(tmpmodelpath, ".bsp") != -1)
		{
			formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\r%s\w]", "Создать BSPMODEL_SOLID");
			menu_additem(vmenu, tmpmenuitem, "4")
			formatex(tmpmenuitem, charsmax(tmpmenuitem), "\w[\r%s\w]", "Создать BSPMODEL_LADDER");
			menu_additem(vmenu, tmpmenuitem, "5")
			/*formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w[\r%s\w]", "Создать BSPMODEL_WATER");
			menu_additem(vmenu, tmpmenuitem,"7")*/

			menu_addblank(vmenu, 1);
		}
		else
		{
			menu_addblank(vmenu, 1);
			menu_addblank(vmenu, 1);
			menu_addblank(vmenu, 1);
		}

		menu_addblank(vmenu, 1);

		menu_additem(vmenu, "Выход", "EXIT")

		menu_setprop(vmenu, MPROP_PERPAGE, 0);
		menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из UNREAL AD меню")
		menu_setprop(vmenu, MPROP_EXIT, MEXIT_ALL)

		menu_display(id, vmenu, 0)
	}
}

public MENU_CREATEAD_HANDLER(id, vmenu, item)
{
	if (item == MENU_EXIT || !is_user_connected(id))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)

	if (equali(data, "exit"))
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}

	new key = str_to_num(data)
	switch (key)
	{
		case 1:
			{
				CREATE_NEW_AD(id, "SPRITE");
				MENU_CREATEAD(id);
			}

		case 2:
			{
				CREATE_NEW_AD(id, "MODEL");
				MENU_CREATEAD(id);
			}

		case 3:
			{
				CREATE_NEW_AD(id, "MODEL_SOLID");
				MENU_CREATEAD(id);
			}

		case 4:
			{
				CREATE_NEW_AD(id, "BSPMODEL_SOLID");
				MENU_CREATEAD(id);
			}

		case 5:
			{
				CREATE_NEW_AD(id, "BSPMODEL_LADDER");
				MENU_CREATEAD(id);
			}

		case 7:
			{
				CREATE_NEW_AD(id, "BSPMODEL_WATER");
				MENU_CREATEAD(id);
			}

		case 101:
			{
				g_iSelectedMenu[id]++;
				if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
				{
					g_iSelectedMenu[id] = 0;
				}

				MENU_AD_MENU_SELECT(id);
			}

		case 102:
			{
				g_iPlayerSelectID[id]++;
				if (g_iPlayerSelectID[id] < 0 || g_iPlayerSelectID[id] >= g_iPrecachedModels)
				{
					g_iPlayerSelectID[id] = 0;
				}

				MENU_CREATEAD(id);
			}
	}

	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public cache_player_teams(id)
{
	new mPlayers[32];
	new mCount;
	get_players(mPlayers, mCount);
	for (new i = 0; i < mCount; i++)
	{
		g_iPlayerTeams[mPlayers[i]] = get_member(mPlayers[i], m_iTeam)
	}
}

public plugin_end()
{
	get_configsdir(g_sAdsPath, charsmax(g_sAdsPath));
	add(g_sAdsPath, charsmax(g_sAdsPath), "/unreal_map_mdls.json");
	json_serial_to_file(g_jAdsList, g_sAdsPath, true);
	json_free(g_jAdsList);
}

public plugin_precache()
{
	get_configsdir(g_sAdsPath, charsmax(g_sAdsPath));
	add(g_sAdsPath, charsmax(g_sAdsPath), "/unreal_map_mdls.json");

	g_jAdsList = json_parse(g_sAdsPath, true);
	if (g_jAdsList == Invalid_JSON)
	{
		g_jAdsList = json_init_object();
	}

	rh_get_mapname(g_sMapName, charsmax(g_sMapName), MNT_TRUE);

	/*
	TESTS STUFF
	if (get_ads_count() == 0)
	{
		set_ads_count(1);
		set_ad_model(0,"models/player/gign/gign.mdl");
		set_ad_type(0,"MODEL");

		new pEnt = MaxClients;
		new Float:vOrigin[3]
		while((pEnt = rg_find_ent_by_class(pEnt, "info_player_start", .useHashTable = false)))
		{
			get_entvar(pEnt, var_origin, vOrigin);
			break;
		}

		//set_ad_lifetime(0,5);
		//set_ad_origin(0,vOrigin);
		//set_ad_rotate_speed(0,0.5);
		//set_ad_rotatedir(0,1);
		set_ad_team(0,TEAM_TERRORIST);
	}*/

	// Precache all models used in ads
	new iAdNum = get_ads_count() - 1;

	new a_curmap_cnt = 0;
	for (; iAdNum >= 0;)
	{
		if (get_ad_disabled(iAdNum) == 0)
		{
			new a_model[MAX_RES_PATH];
			get_ad_model(iAdNum, a_model, charsmax(a_model));
			new a_map[64];
			get_ad_map(iAdNum, a_map, charsmax(a_map));
			if (file_exists(a_model))
			{
				if (equal(a_map, g_sMapName))
				{
					a_curmap_cnt++;
					set_ad_precache(iAdNum, add_precache_model(a_model));
				}
				else
				{
					set_ad_precache(iAdNum, -1)
				}
			}
			else
			{
				log_error(AMX_ERR_NONE, "[Unreal Map Editor] filename '%s' not found ", a_model);
				set_ad_precache(iAdNum, -1)
			}
		}
		else
		{
			set_ad_precache(iAdNum, -1)
		}

		iAdNum--;
	}

	// Precache all models from directory models/unreal_mdls/global/
	new mapPathModel[256];
	formatex(mapPathModel, charsmax(mapPathModel), "%s/global", UNREAL_MDLS_DIRECTORY);
	if (!dir_exists(mapPathModel))
		mkdir(mapPathModel);
	new fileName[64];
	new handleDir = open_dir(mapPathModel, fileName, charsmax(fileName));
	if (handleDir)
	{
		do {
			if (containi(fileName, ".mdl") == -1 && containi(fileName, ".spr") == -1 &&
				containi(fileName, ".bsp") == -1)
			{
				continue;
			}

			if (containi(fileName, ".ztmp") != -1)
			{
				continue;
			}

			new a_model[MAX_RES_PATH];
			formatex(a_model, charsmax(a_model), "%s/global/%s", UNREAL_MDLS_DIRECTORY, fileName);
			if (file_exists(a_model))
				add_precache_model(a_model);
			else
				log_error(AMX_ERR_NONE, "[Unreal Map Editor] filename '%s' not found ", a_model);
		}
		while (next_file(handleDir, fileName, charsmax(fileName)));
		close_dir(handleDir);
	}

	// Precache all models from directory models/unreal_mdls/mapname/

	formatex(mapPathModel, charsmax(mapPathModel), "%s/%s", UNREAL_MDLS_DIRECTORY, g_sMapName);
	if (!dir_exists(mapPathModel))
		mkdir(mapPathModel);
	handleDir = open_dir(mapPathModel, fileName, charsmax(fileName));
	if (handleDir)
	{
		do {
			if (containi(fileName, ".mdl") == -1 && containi(fileName, ".spr") == -1 &&
				containi(fileName, ".bsp") == -1)
			{
				continue;
			}

			if (containi(fileName, ".ztmp") != -1)
			{
				continue;
			}

			new a_model[MAX_RES_PATH];
			formatex(a_model, charsmax(a_model), "%s/%s/%s", UNREAL_MDLS_DIRECTORY, g_sMapName, fileName);
			if (file_exists(a_model))
				add_precache_model(a_model);
			else
				log_error(AMX_ERR_NONE, "[Unreal Map Editor] filename '%s' not found ", a_model);
		}
		while (next_file(handleDir, fileName, charsmax(fileName)));
		close_dir(handleDir);
	}

	log_amx("[%s] Loaded %d objects total, %d for current map, and %d models.", PLUGIN, get_ads_count(), a_curmap_cnt, g_iPrecachedModels);
	for (new i = 0; i < 33; i++)
	{
		search_next_ad(i);
	}
}

public remove_all_ads()
{
	new pEnt = MaxClients;

	while ((pEnt = rg_find_ent_by_class(pEnt, UNREAL_MDLS_CUSTOM_CLASSNAME, .useHashTable = false)))
	{
		RemoveThinkEx(pEnt);
		/*set_entvar(pEnt, var_flags, FL_KILLME);
		set_entvar(pEnt, var_nextthink, get_gametime())*/
		engfunc(EngFunc_RemoveEntity, pEnt)
	}
}

rg_set_ent_rendering(const index, fx = kRenderFxNone, { Float, _}: color[3] = { 0.0, 0.0, 0.0 }, render = kRenderNormal, Float: amount = 0.0)
{
	set_entvar(index, var_renderfx, fx);
	set_entvar(index, var_rendercolor, color);
	set_entvar(index, var_rendermode, render);
	set_entvar(index, var_renderamt, amount);
}

public create_one_ad(id)
{
	new pPrecacheId = get_ad_precache(id);
	if (pPrecacheId == -1)
	{
		return;
	}

	new mPlayers[32];
	new mCount;
	get_players(mPlayers, mCount, "h");
	if (get_ad_maxonline(id) > 0 && mCount > get_ad_maxonline(id))
	{
		return;
	}

	if (mCount < get_ad_minonline(id))
	{
		return;
	}

	new pEnt = 0;

	new sModelType[MAX_RES_PATH];
	get_ad_type(id, sModelType, charsmax(sModelType));

	pEnt = rg_create_entity("func_wall", .useHashTable = false);

	if (!pEnt || is_nullent(pEnt))
	{
		return;
	}

	new sModelPath[MAX_RES_PATH];
	get_ad_model(id, sModelPath, charsmax(sModelPath));

	set_entvar(pEnt, var_model, sModelPath);
	set_entvar(pEnt, var_modelindex, pPrecacheId);
	
	dllfunc(DLLFunc_Spawn, pEnt)

	if (get_entvar(pEnt, var_flags) &FL_WORLDBRUSH)
		set_entvar(pEnt, var_flags, get_entvar(pEnt, var_flags) - FL_WORLDBRUSH);

	new Float: vOrigin[3];
	get_ad_origin(id, vOrigin);

	new Float: vAngles[3];
	get_ad_angles(id, vAngles);

	set_entvar(pEnt, var_origin, vOrigin);
	set_entvar(pEnt, var_angles, vAngles);
	set_entvar(pEnt, var_iuser1, (containi(sModelPath, ".spr") != -1 ? (engfunc(EngFunc_ModelFrames, pPrecacheId) - 1) : 0));
	set_entvar(pEnt, var_iuser2, get_ad_team(id) + UNREAL_MDL_MAGIC_NUMBER);
	set_entvar(pEnt, var_sequence, get_ad_sequence(id));
	set_entvar(pEnt, var_framerate, get_ad_framerate(id));

	if (get_ad_firstframe(id) > float(get_entvar(pEnt, var_iuser1)))
	{
		set_ad_firstframe(id, 0.0);
	}

	set_entvar(pEnt, var_frame, get_ad_firstframe(id));

	new Float: vUserData[3];

	vUserData[0] = float(get_ad_starttime(id));
	vUserData[1] = float(get_ad_lifetime(id));
	vUserData[2] = get_ad_rotate_speed(id);

	set_entvar(pEnt, var_vuser2, vUserData);

	vUserData[0] = get_ad_move_speed(id) *10.0;
	vUserData[1] = float(get_ad_rotatedir(id));
	vUserData[2] = float(get_ad_movedir(id));

	set_entvar(pEnt, var_vuser1, vUserData);
	vUserData[0] = float(get_ad_reversemovedir(id));
	set_entvar(pEnt, var_vuser3, vUserData);

	set_entvar(pEnt, var_movetype, MOVETYPE_FLY);

	set_entvar(pEnt, var_classname, UNREAL_MDLS_CUSTOM_CLASSNAME);

	SetThink(pEnt, "EMPTY_THINK");

	if (equal(sModelType, "SPRITE"))
	{
		set_entvar(pEnt, var_solid, SOLID_NOT);
		rg_set_ent_rendering(pEnt, kRenderFxNoDissipation, Float: { 255.0, 255.0, 255.0 }, kRenderTransAdd, 255.0);
		new Float: fFrameRate = get_entvar(pEnt, var_framerate);
		if (fFrameRate > 0.01 || fFrameRate <= -0.01)
		{
			SetThinkEx(pEnt, "AD_THINK_SPRITE");
		}
		else
		{
			SetThinkEx(pEnt, "AD_THINK");
		}
	}
	else if (equal(sModelType, "MODEL_SOLID"))
	{
		set_entvar(pEnt, var_solid, SOLID_BBOX);
		set_entvar(pEnt, var_mins, Float: {-32.0, -32.0, -32.0 });
		set_entvar(pEnt, var_maxs, Float: {32.0, 32.0, 32.0 });
		SetThinkEx(pEnt, "AD_THINK");
	}
	else if (equal(sModelType, "BSPMODEL_SOLID"))
	{
		set_entvar(pEnt, var_solid, SOLID_BSP);
		set_entvar(pEnt, var_movetype, MOVETYPE_PUSH);
		set_entvar(pEnt, var_skin, CONTENTS_SOLID);
		SetThinkEx(pEnt, "AD_THINK");
		set_entvar(pEnt, var_flags, get_entvar(pEnt, var_flags) + FL_WORLDBRUSH);
	}
	else if (equal(sModelType, "BSPMODEL_LADDER"))
	{
		rg_set_ent_rendering(pEnt, kRenderFxNone, Float: { 255.0, 255.0, 255.0 }, kRenderTransTexture, 255.0);
		set_entvar(pEnt, var_solid, SOLID_BSP);
		set_entvar(pEnt, var_movetype, MOVETYPE_PUSH);
		set_entvar(pEnt, var_skin, CONTENTS_SOLID);
		SetThinkEx(pEnt, "AD_THINK");
		SetTouch(pEnt, "AD_TOUCH_LADDER");
		set_entvar(pEnt, var_flags, get_entvar(pEnt, var_flags) + FL_WORLDBRUSH);
	}
	else if (equal(sModelType, "BSPMODEL_WATER"))
	{
		set_entvar(pEnt, var_solid, SOLID_TRIGGER);
		set_entvar(pEnt, var_skin, CONTENTS_WATER);
		set_entvar(pEnt, var_movetype, MOVETYPE_PUSH);
		SetThinkEx(pEnt, "AD_THINK");
	}
	else
	{
		set_entvar(pEnt, var_solid, SOLID_NOT);
		SetThinkEx(pEnt, "AD_THINK");
	}

	set_entvar(pEnt, var_iuser3, get_entvar(pEnt, var_solid));
	if (get_ad_starttime(id) != 0)
	{
		set_entvar(pEnt, var_solid, SOLID_NOT);
		set_entvar(pEnt, var_effects, get_entvar(pEnt, var_effects) + EF_NODRAW);
	}

	entity_set_origin(pEnt, vOrigin);
}

public EMPTY_THINK(id) {}

new bool: g_bThinksRemoved = false;
public RemoveThinkEx(id)
{
	//if (id == 0)
	//	g_bThinksRemoved = true;
	remove_task(id + TASK_THINK);
}

public SetThinkEx(id, thinkname[])
{
	set_task_ex(0.075, thinkname, .id = TASK_THINK + id, .flags = SetTask_Repeat);
}

public reset_velocity(idx)
{
	new other = idx - TASK_RESET_VELOCITY;
	if (is_user_connected(other))
	{
		set_entvar(other, var_basevelocity, Float:{ 0.0, 0.0, 0.0 });
		if (task_exists(TASK_SET_VELOCITY + other))
		{
			remove_task(TASK_SET_VELOCITY + other);
		}

		unstuckplayer(other);
	}
}

public set_velocity(idx)
{
	new other = idx - TASK_SET_VELOCITY;
	if (is_user_connected(other) && is_user_alive(other))
	{
		new Float: vOrigin[3];
		new Float: vOrigin2[3];
		get_entvar(other, var_origin, vOrigin);
		if (get_distance_f(vOrigin, vOrigin2) < 4.5)
		{
			vOrigin[2] -= 5.0;
		}
		else
		{
			vOrigin[2] += 5.0;
		}

		set_entvar(other, var_origin, vOrigin);
	}
}

public AD_TOUCH_LADDER(const ent, const other)
{
	if (other > 0 && other < 33)
	{
		set_entvar(other, var_basevelocity, Float:
		{
			0.0, 0.0, 20.0 });
		if (task_exists(TASK_RESET_VELOCITY + other))
		{
			remove_task(TASK_RESET_VELOCITY + other);
		}

		set_task_ex(1.0, "reset_velocity", .id = TASK_RESET_VELOCITY + other);
		if (!task_exists(TASK_SET_VELOCITY + other))
		{
			set_task_ex(0.5, "set_velocity", .id = TASK_SET_VELOCITY + other, .flags = SetTask_Repeat);
		}
	}
}

public AD_THINK(const pEntTask)
{
	if (g_bThinksRemoved)
	{
		remove_task(pEntTask);
		return;
	}

	new pEnt = pEntTask - TASK_THINK;
	AD_THINK_WORKER(pEnt);
}

public AD_THINK_SPRITE(const pEntTask)
{
	if (g_bThinksRemoved)
	{
		remove_task(pEntTask);
		return;
	}

	new pEnt = pEntTask - TASK_THINK;
	new Float: fFrameRate = get_entvar(pEnt, var_framerate);
	new iMaxFrames = get_entvar(pEnt, var_iuser1);
	if (iMaxFrames > 0)
	{
		new Float: fFrame = get_entvar(pEnt, var_frame);
		new Float: fIncr = fFrameRate *0.075;
		if (fFrame > iMaxFrames)
			fFrame = 0.0;
		set_entvar(pEnt, var_frame, fFrame + fIncr);
	}

	AD_THINK_WORKER(pEnt);
}

public AD_THINK_WORKER(const pEnt)
{
	new Float: vUserData[3];
	new Float: vUserData2[3];
	new Float: vUserData3[3];
	get_entvar(pEnt, var_vuser2, vUserData);

	new iStartTime = floatround(vUserData[0]);
	new iLifeRound = floatround(vUserData[1]);

	get_entvar(pEnt, var_vuser1, vUserData2);
	get_entvar(pEnt, var_vuser3, vUserData3);

	new iRotateDir = floatround(vUserData2[1]);
	new iMoveDir = floatround(vUserData2[2]);
	new iReverseMoveDir = floatround(vUserData3[0]);

	new Float: fRotateSpeed = vUserData[2];
	new Float: fMoveSpeed = vUserData2[0];

	if (iRotateDir > 0 && fRotateSpeed != 0.0)
	{
		iRotateDir--;
		new Float: vAngles[3];
		if (!(get_entvar(pEnt, var_flags) &FL_WORLDBRUSH))
		{
			get_entvar(pEnt, var_avelocity, vAngles);
			if (iRotateDir > 2)
			{
				switch (iRotateDir)
				{
					case 3:
						{
							vAngles[0] = fRotateSpeed;
							vAngles[1] = fRotateSpeed;
							vAngles[2] = 0.0;
						}

					case 4:
						{
							vAngles[0] = fRotateSpeed;
							vAngles[1] = 0.0;
							vAngles[2] = fRotateSpeed;
						}

					case 5:
						{
							vAngles[0] = 0.0;
							vAngles[1] = fRotateSpeed;
							vAngles[2] = fRotateSpeed;
						}

					default:
						{
							vAngles[0] = fRotateSpeed;
							vAngles[1] = fRotateSpeed;
							vAngles[2] = fRotateSpeed;
						}
				}
			}
			else
			{
				vAngles[0] = vAngles[1] = vAngles[1] = 0.0;
				vAngles[iRotateDir] = fRotateSpeed;
			}

			set_entvar(pEnt, var_avelocity, vAngles);
		}
		else
		{
			get_entvar(pEnt, var_angles, vAngles);
			if (iRotateDir > 2)
			{
				switch (iRotateDir)
				{
					case 3:
						{
							vAngles[0] += fRotateSpeed;
							vAngles[1] += fRotateSpeed;
						}

					case 4:
						{
							vAngles[0] += fRotateSpeed;
							vAngles[2] += fRotateSpeed;
						}

					case 5:
						{
							vAngles[1] += fRotateSpeed;
							vAngles[2] += fRotateSpeed;
						}

					default:
						{
							vAngles[0] += fRotateSpeed;
							vAngles[1] += fRotateSpeed;
							vAngles[2] += fRotateSpeed;
						}
				}
			}
			else
				vAngles[iRotateDir] += fRotateSpeed;

			set_entvar(pEnt, var_angles, vAngles);
		}
	}

	if (iMoveDir > 0 && fMoveSpeed != 0.0)
	{
		iMoveDir--;

		new Float: vOrigin2[3];
		new Float: vOrigin3[3];

		if (!(get_entvar(pEnt, var_flags) &FL_WORLDBRUSH))
			get_entvar(pEnt, var_velocity, vOrigin3);
		else
			get_entvar(pEnt, var_origin, vOrigin3);

		if (!(get_entvar(pEnt, var_flags) &FL_WORLDBRUSH) && iReverseMoveDir > 0 && vOrigin3[0] != fMoveSpeed &&
			vOrigin3[1] != fMoveSpeed &&
			vOrigin3[2] != fMoveSpeed)
		{
			new Float: vOrigin[3];
			set_entvar(pEnt, var_solid, get_entvar(pEnt, var_iuser3));
			get_entvar(pEnt, var_origin, vOrigin);
			get_entvar(pEnt, var_oldorigin, vOrigin2);
			if (get_distance_f(vOrigin, vOrigin2) < 0.5)
			{
				new iEntTryMoveCount = get_entvar(pEnt, var_iuser4);
				if (iEntTryMoveCount > 4)
				{
					set_entvar(pEnt, var_iuser4, 0);
					fMoveSpeed *= -1;
					vUserData2[0] = fMoveSpeed;
					set_entvar(pEnt, var_vuser1, vUserData2);
					new Float: vAngles[3];
					get_entvar(pEnt, var_angles, vAngles);

					if (iReverseMoveDir > 2)
					{
						switch (iReverseMoveDir)
						{
							case 3:
								{
									vAngles[0] += 180.0;
									vAngles[1] += 180.0;
								}

							case 4:
								{
									vAngles[0] += 180.0;
									vAngles[2] += 180.0;
								}

							case 5:
								{
									vAngles[1] += 180.0;
									vAngles[2] += 180.0;
								}

							default:
								{
									vAngles[0] += 180.0;
									vAngles[1] += 180.0;
									vAngles[2] += 180.0;
								}
						}
					}
					else
					{
						vAngles[iReverseMoveDir] -= 180.0;
					}

					set_entvar(pEnt, var_angles, vAngles);
					set_entvar(pEnt, var_solid, SOLID_NOT);
				}
				else
				{
					set_entvar(pEnt, var_iuser4, iEntTryMoveCount + 1);
				}
			}

			set_entvar(pEnt, var_oldorigin, vOrigin);
		}

		if (!(get_entvar(pEnt, var_flags) &FL_WORLDBRUSH))
		{
			if (iMoveDir > 2)
			{
				switch (iMoveDir)
				{
					case 3:
						{
							vOrigin3[0] = fMoveSpeed;
							vOrigin3[1] = fMoveSpeed;
							vOrigin3[2] = 0.0;
						}

					case 4:
						{
							vOrigin3[0] = fMoveSpeed;
							vOrigin3[1] = 0.0;
							vOrigin3[2] = fMoveSpeed;
						}

					case 5:
						{
							vOrigin3[0] = 0.0;
							vOrigin3[1] = fMoveSpeed;
							vOrigin3[2] = fMoveSpeed;
						}

					default:
						{
							vOrigin3[0] = fMoveSpeed;
							vOrigin3[1] = fMoveSpeed;
							vOrigin3[2] = fMoveSpeed;
						}
				}
			}
			else
			{
				vOrigin3[0] = vOrigin3[1] = vOrigin3[1] = 0.0;
				vOrigin3[iMoveDir] = fMoveSpeed;
			}
		}
		else
		{
			if (iMoveDir > 2)
			{
				switch (iMoveDir)
				{
					case 3:
						{
							vOrigin3[0] += fMoveSpeed;
							vOrigin3[1] += fMoveSpeed;
						}

					case 4:
						{
							vOrigin3[0] += fMoveSpeed;
							vOrigin3[2] += fMoveSpeed;
						}

					case 5:
						{
							vOrigin3[1] += fMoveSpeed;
							vOrigin3[2] += fMoveSpeed;
						}

					default:
						{
							vOrigin3[0] += fMoveSpeed;
							vOrigin3[1] += fMoveSpeed;
							vOrigin3[2] += fMoveSpeed;
						}
				}
			}
			else
			{
				vOrigin3[iMoveDir] += fMoveSpeed;
			}
		}

		if (!(get_entvar(pEnt, var_flags) &FL_WORLDBRUSH))
			set_entvar(pEnt, var_velocity, vOrigin3);
		else
		{
			set_entvar(pEnt, var_origin, vOrigin3);
			entity_set_origin(pEnt, vOrigin3);
		}
	}

	if (iStartTime != 0)
	{
		new uEffFlags = get_entvar(pEnt, var_effects);
		if (uEffFlags & EF_NODRAW)
		{
			if (iStartTime < get_gametime() - g_fRoundStartTime)
			{
				set_entvar(pEnt, var_effects, uEffFlags - EF_NODRAW);
				set_entvar(pEnt, var_solid, get_entvar(pEnt, var_iuser3));
				set_task_ex(0.2, "unstuck_all", .id = TASK_UNSTUCK);
			}
		}
	}

	if (iLifeRound != 0 && iLifeRound < get_gametime() - g_fRoundStartTime)
	{
		RemoveThinkEx(pEnt);
		set_entvar(pEnt, var_nextthink, get_gametime());
		set_entvar(pEnt, var_flags, FL_KILLME);
	}
}

public create_all_ads()
{
	new iAdNum = get_ads_count() - 1;
	for (; iAdNum >= 0;)
	{
		new a_map[64];
		get_ad_map(iAdNum, a_map, charsmax(a_map));
		if (get_ad_disabled(iAdNum) == 0 && equal(a_map, g_sMapName))
		{
			if (g_iRoundID >= get_ad_starround(iAdNum) && (get_ad_endround(iAdNum) <= g_iRoundID || get_ad_endround(iAdNum) == 0))
				create_one_ad(iAdNum);
		}

		iAdNum--;
	}
}

public unstuck_all(idx)
{
	new id = idx - TASK_UNSTUCK;
	if (id == 0)
	{
		new mPlayers[32];
		new mCount;
		get_players(mPlayers, mCount, "ah");
		for (new i = 0; i < mCount; i++)
		{
			unstuckplayer(mPlayers[i]);
		}
	}
	else if (is_user_connected(id) && is_user_alive(id))
	{
		unstuckplayer(id);
	}
}

public update_all_ads(idx)
{
	g_fRoundStartTime = get_gametime();
	remove_all_ads();
	create_all_ads();
	
	
	if (task_exists(TASK_UNSTUCK + idx))
	{
		remove_task(TASK_UNSTUCK + idx);
	}
	set_task_ex(0.1, "unstuck_all", .id = TASK_UNSTUCK + idx);
}

public get_ads_count()
{
	return json_object_get_number(g_jAdsList, "ADS_NUM");
}

public set_ads_count(count)
{
	json_object_set_number(g_jAdsList, "ADS_NUM", count);
}

new static_ad_type[64];
public get_ad_type(id, str[], len)
{
	formatex(static_ad_type, charsmax(static_ad_type), "%d_TYPE", id);
	json_object_get_string(g_jAdsList, static_ad_type, str, len);
}

public set_ad_type(id, str[])
{
	formatex(static_ad_type, charsmax(static_ad_type), "%d_TYPE", id);
	json_object_set_string(g_jAdsList, static_ad_type, str);
}

new static_ad_model[MAX_RES_PATH];
public get_ad_model(id, str[], len)
{
	formatex(static_ad_model, charsmax(static_ad_model), "%d_MODEL", id);
	json_object_get_string(g_jAdsList, static_ad_model, str, len);
}

public set_ad_model(id, str[])
{
	formatex(static_ad_model, charsmax(static_ad_model), "%d_MODEL", id);
	json_object_set_string(g_jAdsList, static_ad_model, str);
}

new static_ad_map[64];
public get_ad_map(id, str[], len)
{
	formatex(static_ad_map, charsmax(static_ad_map), "%d_MAP", id);
	json_object_get_string(g_jAdsList, static_ad_map, str, len);
}

public set_ad_map(id, str[])
{
	formatex(static_ad_map, charsmax(static_ad_map), "%d_MAP", id);
	json_object_set_string(g_jAdsList, static_ad_map, str);
}

new static_ad_precache[64];
public get_ad_precache(id)
{
	formatex(static_ad_precache, charsmax(static_ad_precache), "%d_precacheId", id);
	return json_object_get_number(g_jAdsList, static_ad_precache);
}

public set_ad_precache(id, precacheId)
{
	formatex(static_ad_precache, charsmax(static_ad_precache), "%d_precacheId", id);
	json_object_set_number(g_jAdsList, static_ad_precache, precacheId);
}

new static_ad_disabled[64];
public get_ad_disabled(id)
{
	formatex(static_ad_disabled, charsmax(static_ad_disabled), "%d_disabled", id);
	return json_object_get_number(g_jAdsList, static_ad_disabled);
}

public set_ad_disabled(id, disabled)
{
	formatex(static_ad_disabled, charsmax(static_ad_disabled), "%d_disabled", id);
	json_object_set_number(g_jAdsList, static_ad_disabled, disabled);
}

new static_ad_team[64];
public get_ad_team(id)
{
	formatex(static_ad_team, charsmax(static_ad_team), "%d_team", id);
	return json_object_get_number(g_jAdsList, static_ad_team);
}

public set_ad_team(id, team)
{
	formatex(static_ad_team, charsmax(static_ad_team), "%d_team", id);
	json_object_set_number(g_jAdsList, static_ad_team, team);
}

new static_ad_framerate[64];
public Float: get_ad_framerate(id)
{
	formatex(static_ad_framerate, charsmax(static_ad_framerate), "%d_framerate", id);
	return json_object_get_real(g_jAdsList, static_ad_framerate);
}

public set_ad_framerate(id, Float: framerate)
{
	formatex(static_ad_framerate, charsmax(static_ad_framerate), "%d_framerate", id);
	json_object_set_real(g_jAdsList, static_ad_framerate, framerate);
}

new static_ad_firstframe[64];
public Float: get_ad_firstframe(id)
{
	formatex(static_ad_firstframe, charsmax(static_ad_firstframe), "%d_firstframe", id);
	return json_object_get_real(g_jAdsList, static_ad_firstframe);
}

public set_ad_firstframe(id, Float: firstframe)
{
	formatex(static_ad_firstframe, charsmax(static_ad_firstframe), "%d_firstframe", id);
	json_object_set_real(g_jAdsList, static_ad_firstframe, firstframe);
}

new static_ad_sequence[64];
public get_ad_sequence(id)
{
	formatex(static_ad_sequence, charsmax(static_ad_sequence), "%d_seqnum", id);
	return json_object_get_number(g_jAdsList, static_ad_sequence);
}

public set_ad_sequence(id, seq)
{
	formatex(static_ad_sequence, charsmax(static_ad_sequence), "%d_seqnum", id);
	json_object_set_number(g_jAdsList, static_ad_sequence, seq);
}

new static_ad_rotatedir[64];
public get_ad_rotatedir(id)
{
	formatex(static_ad_rotatedir, charsmax(static_ad_rotatedir), "%d_rotatedir", id);
	return json_object_get_number(g_jAdsList, static_ad_rotatedir);
}

public set_ad_rotatedir(id, rotatedir)
{
	formatex(static_ad_rotatedir, charsmax(static_ad_rotatedir), "%d_rotatedir", id);
	json_object_set_number(g_jAdsList, static_ad_rotatedir, rotatedir);
}

new static_ad_rotate_speed[64];
public Float: get_ad_rotate_speed(id)
{
	formatex(static_ad_rotate_speed, charsmax(static_ad_rotate_speed), "%d_rotate_speed", id);
	return json_object_get_real(g_jAdsList, static_ad_rotate_speed);
}

public set_ad_rotate_speed(id, Float: rotspeed)
{
	formatex(static_ad_rotate_speed, charsmax(static_ad_rotate_speed), "%d_rotate_speed", id);
	json_object_set_real(g_jAdsList, static_ad_rotate_speed, rotspeed);
}

new static_ad_minonline[64];
public get_ad_minonline(id)
{
	formatex(static_ad_minonline, charsmax(static_ad_minonline), "%d_minonline", id);
	return json_object_get_number(g_jAdsList, static_ad_minonline);
}

public set_ad_minonline(id, minonline)
{
	formatex(static_ad_minonline, charsmax(static_ad_minonline), "%d_minonline", id);
	json_object_set_number(g_jAdsList, static_ad_minonline, minonline);
}

new static_ad_maxonline[64];
public get_ad_maxonline(id)
{
	formatex(static_ad_maxonline, charsmax(static_ad_maxonline), "%d_maxonline", id);
	return json_object_get_number(g_jAdsList, static_ad_maxonline);
}

public set_ad_maxonline(id, maxonline)
{
	formatex(static_ad_maxonline, charsmax(static_ad_maxonline), "%d_maxonline", id);
	json_object_set_number(g_jAdsList, static_ad_maxonline, maxonline);
}

new static_ad_movedir[64];
public get_ad_movedir(id)
{
	formatex(static_ad_movedir, charsmax(static_ad_movedir), "%d_movedir", id);
	return json_object_get_number(g_jAdsList, static_ad_movedir);
}

public set_ad_movedir(id, movedir)
{
	formatex(static_ad_movedir, charsmax(static_ad_movedir), "%d_movedir", id);
	json_object_set_number(g_jAdsList, static_ad_movedir, movedir);
}

new static_ad_reversemovedir[64];
public get_ad_reversemovedir(id)
{
	formatex(static_ad_reversemovedir, charsmax(static_ad_reversemovedir), "%d_reversdir", id);
	return json_object_get_number(g_jAdsList, static_ad_reversemovedir);
}

public set_ad_reversemovedir(id, movedir)
{
	formatex(static_ad_reversemovedir, charsmax(static_ad_reversemovedir), "%d_reversdir", id);
	json_object_set_number(g_jAdsList, static_ad_reversemovedir, movedir);
}

new static_ad_move_speed[64];
public Float: get_ad_move_speed(id)
{
	formatex(static_ad_move_speed, charsmax(static_ad_move_speed), "%d_move_speed", id);
	return json_object_get_real(g_jAdsList, static_ad_move_speed);
}

public set_ad_move_speed(id, Float: rotspeed)
{
	formatex(static_ad_move_speed, charsmax(static_ad_move_speed), "%d_move_speed", id);
	json_object_set_real(g_jAdsList, static_ad_move_speed, rotspeed);
}

new static_ad_starttime[64];
public get_ad_starttime(id)
{
	formatex(static_ad_starttime, charsmax(static_ad_starttime), "%d_starttime", id);
	return json_object_get_number(g_jAdsList, static_ad_starttime);
}

public set_ad_starttime(id, starttime)
{
	formatex(static_ad_starttime, charsmax(static_ad_starttime), "%d_starttime", id);
	json_object_set_number(g_jAdsList, static_ad_starttime, starttime);
}

new static_ad_starround[64];
public get_ad_starround(id)
{
	formatex(static_ad_starround, charsmax(static_ad_starround), "%d_starround", id);
	return json_object_get_number(g_jAdsList, static_ad_starround);
}

public set_ad_starround(id, starround)
{
	formatex(static_ad_starround, charsmax(static_ad_starround), "%d_starround", id);
	json_object_set_number(g_jAdsList, static_ad_starround, starround);
}


new static_ad_endround[64];
public get_ad_endround(id)
{
	formatex(static_ad_endround, charsmax(static_ad_endround), "%d_endround", id);
	return json_object_get_number(g_jAdsList, static_ad_endround);
}

public set_ad_endround(id, endround)
{
	formatex(static_ad_endround, charsmax(static_ad_endround), "%d_endround", id);
	json_object_set_number(g_jAdsList, static_ad_endround, endround);
}

new static_ad_lifetime[64];
public get_ad_lifetime(id)
{
	formatex(static_ad_lifetime, charsmax(static_ad_lifetime), "%d_lifetime", id);
	return json_object_get_number(g_jAdsList, static_ad_lifetime);
}

public set_ad_lifetime(id, lifetime)
{
	formatex(static_ad_lifetime, charsmax(static_ad_lifetime), "%d_lifetime", id);
	json_object_set_number(g_jAdsList, static_ad_lifetime, lifetime);
}

new static_ad_origin[64];
public get_ad_origin(id, Float: origin[3])
{
	formatex(static_ad_origin, charsmax(static_ad_origin), "%d_origin_x", id);
	origin[0] = json_object_get_real(g_jAdsList, static_ad_origin);
	formatex(static_ad_origin, charsmax(static_ad_origin), "%d_origin_y", id);
	origin[1] = json_object_get_real(g_jAdsList, static_ad_origin);
	formatex(static_ad_origin, charsmax(static_ad_origin), "%d_origin_z", id);
	origin[2] = json_object_get_real(g_jAdsList, static_ad_origin);
}

public set_ad_origin(id, Float: origin[3])
{
	formatex(static_ad_origin, charsmax(static_ad_origin), "%d_origin_x", id);
	json_object_set_real(g_jAdsList, static_ad_origin, origin[0]);
	formatex(static_ad_origin, charsmax(static_ad_origin), "%d_origin_y", id);
	json_object_set_real(g_jAdsList, static_ad_origin, origin[1]);
	formatex(static_ad_origin, charsmax(static_ad_origin), "%d_origin_z", id);
	json_object_set_real(g_jAdsList, static_ad_origin, origin[2]);
}

new static_ad_angles[64];
public get_ad_angles(id, Float: angles[3])
{
	formatex(static_ad_angles, charsmax(static_ad_angles), "%d_angles_x", id);
	angles[0] = json_object_get_real(g_jAdsList, static_ad_angles);
	formatex(static_ad_angles, charsmax(static_ad_angles), "%d_angles_y", id);
	angles[1] = json_object_get_real(g_jAdsList, static_ad_angles);
	formatex(static_ad_angles, charsmax(static_ad_angles), "%d_angles_z", id);
	angles[2] = json_object_get_real(g_jAdsList, static_ad_angles);
}

public set_ad_angles(id, Float: angles[3])
{
	formatex(static_ad_angles, charsmax(static_ad_angles), "%d_angles_x", id);
	json_object_set_real(g_jAdsList, static_ad_angles, angles[0]);
	formatex(static_ad_angles, charsmax(static_ad_angles), "%d_angles_y", id);
	json_object_set_real(g_jAdsList, static_ad_angles, angles[1]);
	formatex(static_ad_angles, charsmax(static_ad_angles), "%d_angles_z", id);
	json_object_set_real(g_jAdsList, static_ad_angles, angles[2]);
}

new static_precache_name[64];
new static_precache_id[64];
new static_precache_path[MAX_RES_PATH];

public add_precache_model(mdl[])
{
	new return_value = 0;
	for (new i = g_iPrecachedModels - 1; i >= 0;)
	{
		formatex(static_precache_name, charsmax(static_precache_name), "MDL_%d_precachePath", i);
		formatex(static_precache_id, charsmax(static_precache_id), "MDL_%d_precacheId", i);
		json_object_get_string(g_jAdsList, static_precache_name, static_precache_path, charsmax(static_precache_path));
		if (equal(mdl, static_precache_path))
		{
			return json_object_get_number(g_jAdsList, static_precache_id)
		}

		i--;
	}

	formatex(static_precache_name, charsmax(static_precache_name), "MDL_%d_precachePath", g_iPrecachedModels)
	formatex(static_precache_id, charsmax(static_precache_id), "MDL_%d_precacheId", g_iPrecachedModels)

	return_value = precache_model(mdl);
	json_object_set_string(g_jAdsList, static_precache_name, mdl);
	json_object_set_number(g_jAdsList, static_precache_id, return_value);

	g_iPrecachedModels++;
	return return_value;
}

public precache_get_model(id, str[], len)
{
	formatex(static_precache_name, charsmax(static_precache_name), "MDL_%d_precachePath", id)
	json_object_get_string(g_jAdsList, static_precache_name, str, len);
}

/*UNSTUCK STUFF */
#define TSC_Vector_MA(%1,%2,%3,%4)	(%4[0] = %2[0] * %3 + %1[0], %4[1] = %2[1] * %3 + %1[1])

stock is_player_stuck(id, Float: originF[3])
{
	engfunc(EngFunc_TraceHull, originF, originF, 0, (get_entvar(id, var_flags) &FL_DUCKING) ? HULL_HEAD : HULL_HUMAN, id, 0)

	if (get_tr2(0, TR_StartSolid) || get_tr2(0, TR_AllSolid) || !get_tr2(0, TR_InOpen))
		return true

	return false
}

stock is_hull_vacant(Float: origin[3], hull)
{
	engfunc(EngFunc_TraceHull, origin, origin, DONT_IGNORE_MONSTERS, hull, 0, 0)

	if (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen))
		return true

	return false
}

new const Float: RANDOM_OWN_PLACE[][3] = {
{ -96.5, 0.0, 0.0 },
	{ 96.5, 0.0, 0.0 },
	{ 0.0, -96.5, 0.0 },
	{ 0.0, 96.5, 0.0 },
	{-96.5, -96.5, 0.0
	},
	{-96.5, 96.5, 0.0
	},
	{ 96.5, 96.5, 0.0 },
	{ 96.5, -96.5, 0.0 }
};

public unstuckplayer(id)
{
	static Float: Origin[3];
	get_entvar(id, var_origin, Origin);
	static iHull, iSpawnPoint, i;
	iHull = (get_entvar(id, var_flags) &FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;

	// fast unstuck 
	if (is_player_stuck(id, Origin))
	{
		Origin[2] -= 64.0;
	}
	else
	{
		entity_set_origin(id, Origin);
		return;
	}

	if (is_player_stuck(id, Origin))
	{
		Origin[2] += 128.0;
	}
	else
	{
		entity_set_origin(id, Origin);
		return;
	}

	// slow unstuck 
	if (is_player_stuck(id, Origin))
	{
		new Float: flOrigin[3], Float: flOriginFinal[3], iSize;
		get_entvar(id, var_origin, flOrigin);
		iSize = sizeof(RANDOM_OWN_PLACE);

		iSpawnPoint = random_num(0, iSize - 1);

		for (i = iSpawnPoint + 1; /*no condition*/ ; i++)
		{
			if (i >= iSize)
				i = 0;

			flOriginFinal[0] = flOrigin[0] + RANDOM_OWN_PLACE[i][0];
			flOriginFinal[1] = flOrigin[1] + RANDOM_OWN_PLACE[i][1];
			flOriginFinal[2] = flOrigin[2];

			engfunc(EngFunc_TraceLine, flOrigin, flOriginFinal, IGNORE_MONSTERS, id, 0);

			new Float: flFraction;
			get_tr2(0, TR_flFraction, flFraction);
			if (flFraction < 1.0)
			{
				new Float: vTraceEnd[3], Float: vNormal[3];
				get_tr2(0, TR_vecEndPos, vTraceEnd);
				get_tr2(0, TR_vecPlaneNormal, vNormal);

				TSC_Vector_MA(vTraceEnd, vNormal, 32.5, flOriginFinal);
			}

			flOriginFinal[2] -= 35.0;

			new iZ = 0;
			do {
				if (is_hull_vacant(flOriginFinal, iHull))
				{
					i = iSpawnPoint;
					entity_set_origin(id, flOriginFinal);
					break
				}

				flOriginFinal[2] += 40.0;
			}

			while (++iZ <= 2)

			if (i == iSpawnPoint)
				break;
		}
	}
	else
	{
		entity_set_origin(id, Origin);
	}
}