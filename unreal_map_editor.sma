#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <reapi>
#include <json>
#include <fakemeta>
#include <hamsandwich>


#define PLUGIN "Unreal Map Editor"
#define VERSION "0.3"
#define AUTHOR "karaulov"

new JSON:g_jAdsList = Invalid_JSON;
new g_sAdsPath[256];

new g_iPrecachedModels = 0;

new UNREAL_MDLS_DIRECTORY[] = "models/unreal_mdls";
new UNREAL_MDLS_CUSTOM_CLASSNAME[ ] = "unreal_mdl";

new Float:g_fMapStartTime = 0.0;
new Float:g_fRoundStartTime = 0.0;

new TeamName:g_iPlayerTeams[33] = {TEAM_UNASSIGNED,...};
new UNREAL_MDL_MAGIC_NUMBER = 200000;

new UNREAL_MDL_MAX_MENUS = 6;

new UNREAL_MDL_ACCESS_LEVEL = ADMIN_BAN;

new g_iPlayerSelectID[33] = {0,...};

new g_sMapName[33];

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	
	//https://www.gametracker.com/search/?search_by=server_variable&search_by2=unreal_ads&query=&loc=_all&sort=&order=
	//https://gs-monitor.com/?searchType=2&variableName=unreal_ads&variableValue=&submit=&mode=
	create_cvar("unreal_ads", VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Pre");
	register_forward(FM_AddToFullPack, "AddToFullPack_Post", ._post = true);
	
	set_task_ex(1.0, "cache_player_teams", .flags = SetTask_Repeat);
	
	register_clcmd("say /adcreate", "MENU_CREATEAD")
	register_clcmd("unreal_mdl_create", "MENU_CREATEAD")
	
	register_clcmd("say /adedit", "MENU_AD_MENU_SELECT")
	register_clcmd("unreal_mdl_edit", "MENU_AD_MENU_SELECT")
	
	get_mapname(g_sMapName,charsmax(g_sMapName));
	
	g_fMapStartTime = get_gametime();
	update_all_ads();
}

new g_iSelectedAd[33] = {0,...};

new g_iSelectedMenu[33] = {0,...};



public MENU_DISABLEAD_HANDLER(id, vmenu, item) 
{
	if(item == MENU_EXIT || !is_user_connected(id) || !is_user_alive(id)) 
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}
	
	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)
	     
	new key = str_to_num(data)
	switch(key) 
	{	
		case 1:
		{
			set_ad_disabled(g_iSelectedAd[id], get_ad_disabled(g_iSelectedAd[id]) == 0 ? 1 : 0);
			update_all_ads();
			menu_destroy(vmenu);
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED;
		}
		case 2:
		{
			new Float:vOrigin[3];
			get_ad_origin(g_iSelectedAd[id], vOrigin);
			set_entvar(id,var_origin,vOrigin);
			menu_destroy(vmenu);
			MENU_AD_MENU_SELECT(id);
			unstuckplayer(id);
			return PLUGIN_HANDLED;
		}
		case 3:
		{
			new Float:vOrigin[3];
			get_entvar(id,var_origin,vOrigin);
			set_ad_origin(g_iSelectedAd[id],vOrigin);
			update_all_ads();
			menu_destroy(vmenu);
			MENU_AD_MENU_SELECT(id);
			unstuckplayer(id);
			return PLUGIN_HANDLED;
		}
		case 100:
		{
			g_iSelectedAd[id]++;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] = 0;
			}
			menu_destroy(vmenu);
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED;
		}
		case 101:
		{
			g_iSelectedAd[id]--;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] =  get_ads_count() - 1;
			}
			menu_destroy(vmenu);
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED;
		}
		case 102:
		{
			g_iSelectedMenu[id]++;
			if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
			{
				g_iSelectedMenu[id] = 0;
			}
			menu_destroy(vmenu);
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED;
		}
	}
	menu_destroy(vmenu);
	return PLUGIN_HANDLED;
}


public MENU_DISABLEAD(id)
{
	if (get_ads_count() == 0)
	{
		client_print_color(id,print_team_red,"НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return ;
	}
	
	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}
	
	new tmpmodelpath[256];
	get_ad_model(g_iSelectedAd[id],tmpmodelpath,charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\rDisable:%d=[\w%s\r]",g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_DISABLEAD_HANDLER")
			
	menu_additem(vmenu, "\wСледующее меню","102")
	menu_additem(vmenu, "\yСледующая модель","100")
		
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\wСтатус: [\r%s\w]", get_ad_disabled(g_iSelectedAd[id]) > 0 ? "ОТКЛЮЧЕНО" : "ВКЛЮЧЕНО");
	menu_additem(vmenu, tmpmenuitem,"1")
	
	menu_additem(vmenu, "Переместиться к модели","2")
	menu_additem(vmenu, "Переместить модель сюда","3")
	
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rDISABLE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT,MEXIT_ALL)

	menu_display(id,vmenu,0)
}



public MENU_TEAMVISIBLE_HANDLER(id, vmenu, item) 
{
	if(item == MENU_EXIT || !is_user_connected(id) || !is_user_alive(id)) 
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}
	
	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)
	     
	new key = str_to_num(data)
	switch(key) 
	{	
		case 1:
		{
			new teamid = get_ad_team(g_iSelectedAd[id]);
			if (teamid == 0)
			{
				set_ad_team(g_iSelectedAd[id], TEAM_TERRORIST);
			}
			else if (teamid == 1)
			{
				set_ad_team(g_iSelectedAd[id], TEAM_CT);
			}
			else if (teamid == 2)
			{
				set_ad_team(g_iSelectedAd[id], TEAM_SPECTATOR);
			}
			else
			{
				set_ad_team(g_iSelectedAd[id], TEAM_UNASSIGNED);
			}
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 100:
		{
			g_iSelectedAd[id]++;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 101:
		{
			g_iSelectedAd[id]--;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] =  get_ads_count() - 1;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 102:
		{
			g_iSelectedMenu[id]++;
			if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
			{
				g_iSelectedMenu[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
	}
	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}


public MENU_TEAMVISIBLE(id)
{
	if (get_ads_count() == 0)
	{
		client_print_color(id,print_team_red,"НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return ;
	}
	
	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}
	
	new tmpmodelpath[256];
	get_ad_model(g_iSelectedAd[id],tmpmodelpath,charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\rVis:%d=[\w%s\r]",g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_TEAMVISIBLE_HANDLER")
		
			
	menu_additem(vmenu, "\wСледующее меню","102")
	menu_additem(vmenu, "\yСледующая модель","100")
	
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w%s[\r%s\w]", "Команда:", 
		get_ad_team(g_iSelectedAd[id]) == 0 ? "ЛЮБАЯ" : 
		get_ad_team(g_iSelectedAd[id]) == 1 ? "ТЕРРОР" : 
		get_ad_team(g_iSelectedAd[id]) == 2 ?  "КТ" : "ЗРИТЕЛИ");
		
	menu_additem(vmenu, tmpmenuitem,"1")
	
	
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rTEAM\w] меню")
	menu_setprop(vmenu, MPROP_EXIT,MEXIT_ALL)

	menu_display(id,vmenu,0)
}

new g_iSelectedCoord[33] = {0,...};



public MENU_MOVEAD_HANDLER(id, vmenu, item) 
{
	if(item == MENU_EXIT || !is_user_connected(id) || !is_user_alive(id)) 
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}
	
	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)
	     
	new key = str_to_num(data)
	switch(key) 
	{	
		case 1:
		{
			g_iSelectedCoord[id]++;
			if (g_iSelectedCoord[id] > 2)
				g_iSelectedCoord[id] = 0;
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 2:
		{
			new Float:vOrigin[3];
			get_ad_origin(g_iSelectedAd[id],vOrigin);
			vOrigin[g_iSelectedCoord[id]]+=1;
			set_ad_origin(g_iSelectedAd[id],vOrigin);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 3:
		{
			new Float:vOrigin[3];
			get_ad_origin(g_iSelectedAd[id],vOrigin);
			vOrigin[g_iSelectedCoord[id]]+=10;
			set_ad_origin(g_iSelectedAd[id],vOrigin);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 4:
		{
			new Float:vOrigin[3];
			get_ad_origin(g_iSelectedAd[id],vOrigin);
			vOrigin[g_iSelectedCoord[id]]-=1;
			set_ad_origin(g_iSelectedAd[id],vOrigin);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 5:
		{
			new Float:vOrigin[3];
			get_ad_origin(g_iSelectedAd[id],vOrigin);
			vOrigin[g_iSelectedCoord[id]]-=10;
			set_ad_origin(g_iSelectedAd[id],vOrigin);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 100:
		{
			g_iSelectedAd[id]++;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 101:
		{
			g_iSelectedAd[id]--;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] =  get_ads_count() - 1;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 102:
		{
			g_iSelectedMenu[id]++;
			if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
			{
				g_iSelectedMenu[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
	}
	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_MOVEAD(id)
{
	if (get_ads_count() == 0)
	{
		client_print_color(id,print_team_red,"НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return ;
	}
	
	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}
	
	new tmpmodelpath[256];
	get_ad_model(g_iSelectedAd[id],tmpmodelpath,charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\rMove:%d=[\w%s\r]",g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_MOVEAD_HANDLER")
	
	
	menu_additem(vmenu, "\wСледующее меню","102")
	menu_additem(vmenu, "\yСледующая модель","100")
	
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w%s[\r%s\w]", "Координата:", 
		g_iSelectedCoord[id] == 0 ? "X" : 
		g_iSelectedCoord[id] == 1 ? "Y" : "Z");
		
	menu_additem(vmenu, tmpmenuitem,"1")
	
	menu_additem(vmenu, "\wДвигать [\r+1\w]","2")
	menu_additem(vmenu, "\wДвигать [\r+10\w]","3")
	
	menu_additem(vmenu, "\wДвигать [\r-1\w]","4")
	menu_additem(vmenu, "\wДвигать [\r-10\w]","5")
	
	
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rMOVE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT,MEXIT_ALL)

	menu_display(id,vmenu,0)
}



public MENU_FRAMERATEAD_HANDLER(id, vmenu, item) 
{
	if(item == MENU_EXIT || !is_user_connected(id) || !is_user_alive(id)) 
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}
	
	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)
	     
	new key = str_to_num(data)
	switch(key) 
	{	
		case 2:
		{
			set_ad_framerate(g_iSelectedAd[id],get_ad_framerate(g_iSelectedAd[id]) + 0.5);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 3:
		{
			set_ad_framerate(g_iSelectedAd[id],get_ad_framerate(g_iSelectedAd[id]) - 0.5);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 4:
		{
			set_ad_framerate(g_iSelectedAd[id],get_ad_framerate(g_iSelectedAd[id]) + 1.0);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 5:
		{
			set_ad_framerate(g_iSelectedAd[id],get_ad_framerate(g_iSelectedAd[id]) - 1.0);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 100:
		{
			g_iSelectedAd[id]++;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 101:
		{
			g_iSelectedAd[id]--;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] =  get_ads_count() - 1;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 102:
		{
			g_iSelectedMenu[id]++;
			if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
			{
				g_iSelectedMenu[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
	}
	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}


public MENU_FRAMERATEAD(id)
{
	if (get_ads_count() == 0)
	{
		client_print_color(id,print_team_red,"НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return ;
	}
	
	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}
	
	new tmpmodelpath[256];
	get_ad_model(g_iSelectedAd[id],tmpmodelpath,charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\rFPS:%d=[\w%s\r]",g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_FRAMERATEAD_HANDLER")
	
		
	menu_additem(vmenu, "\wСледующее меню","102")
	menu_additem(vmenu, "\yСледующая модель","100")
		
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w%s[\r%.2f\w]", "FPS:", get_ad_framerate(g_iSelectedAd[id]));
		
	menu_additem(vmenu, tmpmenuitem,"1")
	
	menu_additem(vmenu, "\wУвеличить [\r+0.5\w]","2")
	
	menu_additem(vmenu, "\wУменьшить [\r-0.5\w]","3")
	
	menu_additem(vmenu, "\wУвеличить [\r+1\w]","4")
	
	menu_additem(vmenu, "\wУменьшить [\r-1\w]","5")

	
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rFPS\w] меню")
	menu_setprop(vmenu, MPROP_EXIT,MEXIT_ALL)

	menu_display(id,vmenu,0)
}


public MENU_ANGLEAD_HANDLER(id, vmenu, item) 
{
	if(item == MENU_EXIT || !is_user_connected(id) || !is_user_alive(id)) 
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}
	
	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)
	     
	new key = str_to_num(data)
	switch(key) 
	{	
		case 1:
		{
			g_iSelectedCoord[id]++;
			if (g_iSelectedCoord[id] > 2)
				g_iSelectedCoord[id] = 0;
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 2:
		{
			new Float:vAngles[3];
			get_ad_angles(g_iSelectedAd[id],vAngles);
			vAngles[g_iSelectedCoord[id]]+=1;
			set_ad_angles(g_iSelectedAd[id],vAngles);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 3:
		{
			new Float:vAngles[3];
			get_ad_angles(g_iSelectedAd[id],vAngles);
			vAngles[g_iSelectedCoord[id]]+=10;
			set_ad_angles(g_iSelectedAd[id],vAngles);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 4:
		{
			new Float:vAngles[3];
			get_ad_angles(g_iSelectedAd[id],vAngles);
			vAngles[g_iSelectedCoord[id]]-=1;
			set_ad_angles(g_iSelectedAd[id],vAngles);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 5:
		{
			new Float:vAngles[3];
			get_ad_angles(g_iSelectedAd[id],vAngles);
			vAngles[g_iSelectedCoord[id]]-=10;
			set_ad_angles(g_iSelectedAd[id],vAngles);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 100:
		{
			g_iSelectedAd[id]++;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 101:
		{
			g_iSelectedAd[id]--;
			if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >=  get_ads_count())
			{
				g_iSelectedAd[id] =  get_ads_count() - 1;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 102:
		{
			g_iSelectedMenu[id]++;
			if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
			{
				g_iSelectedMenu[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
	}
	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}

public MENU_ANGLEAD(id)
{
	if (get_ads_count() == 0)
	{
		client_print_color(id,print_team_red,"НЕТ ДОСТУПНОЙ РЕКЛАМЫ");
		return ;
	}
	
	if (g_iSelectedAd[id] < 0 || g_iSelectedAd[id] >= get_ads_count())
	{
		g_iSelectedAd[id] = 0;
	}
	
	new tmpmodelpath[256];
	get_ad_model(g_iSelectedAd[id],tmpmodelpath,charsmax(tmpmodelpath));

	new tmpmenuitem[256];
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\rRotate:%d=[\w%s\r]",g_iSelectedAd[id], tmpmodelpath);

	new vmenu = menu_create(tmpmenuitem, "MENU_ANGLEAD_HANDLER")
	
	
	menu_additem(vmenu, "\wСледующее меню","102")
	menu_additem(vmenu, "\yСледующая модель","100")
	
	formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w%s[\r%s\w]", "Координата:", 
		g_iSelectedCoord[id] == 0 ? "X" : 
		g_iSelectedCoord[id] == 1 ? "Y" : "Z");
		
	menu_additem(vmenu, tmpmenuitem,"1")
	
	menu_additem(vmenu, "\wВращать [\r+1\w]","2")
	menu_additem(vmenu, "\wВращать [\r+10\w]","3")
	
	menu_additem(vmenu, "\wВращать [\r-1\w]","4")
	menu_additem(vmenu, "\wВращать [\r-10\w]","5")
	
	
	menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из \w[\rANGLE\w] меню")
	menu_setprop(vmenu, MPROP_EXIT,MEXIT_ALL)

	menu_display(id,vmenu,0)
}

public MENU_AD_MENU_SELECT(id)
{
	if (get_user_flags(id) & UNREAL_MDL_ACCESS_LEVEL)
	{
		if (g_iSelectedMenu[id] == 0)
		{
			MENU_DISABLEAD(id);
		}
		else if(g_iSelectedMenu[id] == 1)
		{
			MENU_TEAMVISIBLE(id);
		}
		else if(g_iSelectedMenu[id] == 2)
		{
			MENU_MOVEAD(id);
		}
		else if(g_iSelectedMenu[id] == 3)
		{
			MENU_ANGLEAD(id);
		}
		else if(g_iSelectedMenu[id] == 4)
		{
			MENU_CREATEAD(id);
		}
		else 
		{
			MENU_FRAMERATEAD(id);
		}
	}
}

public MENU_CREATEAD_HANDLER(id, vmenu, item) 
{
	if(item == MENU_EXIT || !is_user_connected(id) || !is_user_alive(id)) 
	{
		menu_destroy(vmenu)
		return PLUGIN_HANDLED
	}
	
	new data[6], iName[64], access, callback
	menu_item_getinfo(vmenu, item, access, data, 5, iName, 63, callback)
	     
	new key = str_to_num(data)
	switch(key) 
	{	
		case 1:
		{
			new tmpmodelpath[256];
			precache_get_model(g_iPlayerSelectID[id],tmpmodelpath, charsmax(tmpmodelpath));
			new ads = get_ads_count();
			new Float:vOrigin[3];
			get_entvar(id,var_origin,vOrigin);
			set_ads_count(get_ads_count() + 1);
			set_ad_model(ads,tmpmodelpath);
			set_ad_type(ads,"SPRITE");
			set_ad_origin(ads,vOrigin);
			set_ad_angles(ads, Float:{0.0,0.0,0.0});
			set_ad_disabled(ads, 0);
			set_ad_lifetime(ads,0.0);
			set_ad_lifetime_round(ads,0.0);
			set_ad_map(ads,g_sMapName);
			set_ad_precache(ads,add_precache_model(tmpmodelpath));
			set_ad_rotate_speed(ads,0.0);
			set_ad_rotatedir(ads,0);
			set_ad_team(ads,TEAM_UNASSIGNED);
			set_ad_framerate(ads,1.0);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_CREATEAD(id);
			unstuckplayer(id);
			return PLUGIN_HANDLED
		}
		case 2:
		{
			new tmpmodelpath[256];
			precache_get_model(g_iPlayerSelectID[id],tmpmodelpath, charsmax(tmpmodelpath));
			new ads = get_ads_count();
			new Float:vOrigin[3];
			get_entvar(id,var_origin,vOrigin);
			set_ads_count(get_ads_count() + 1);
			set_ad_model(ads,tmpmodelpath);
			set_ad_type(ads,"MODEL");
			set_ad_origin(ads,vOrigin);
			set_ad_angles(ads, Float:{0.0,0.0,0.0});
			set_ad_disabled(ads, 0);
			set_ad_lifetime(ads,0.0);
			set_ad_lifetime_round(ads,0.0);
			set_ad_map(ads,g_sMapName);
			set_ad_precache(ads,add_precache_model(tmpmodelpath));
			set_ad_rotate_speed(ads,0.0);
			set_ad_rotatedir(ads,0);
			set_ad_team(ads,TEAM_UNASSIGNED);
			set_ad_framerate(ads,0.0);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_CREATEAD(id);
			unstuckplayer(id);
			return PLUGIN_HANDLED
		}
		case 3:
		{
			new tmpmodelpath[256];
			precache_get_model(g_iPlayerSelectID[id],tmpmodelpath, charsmax(tmpmodelpath));
			new ads = get_ads_count();
			new Float:vOrigin[3];
			get_entvar(id,var_origin,vOrigin);
			set_ads_count(get_ads_count() + 1);
			set_ad_model(ads,tmpmodelpath);
			set_ad_type(ads,"BSPMODEL_SOLID");
			set_ad_origin(ads,vOrigin);
			set_ad_angles(ads, Float:{0.0,0.0,0.0});
			set_ad_disabled(ads, 0);
			set_ad_lifetime(ads,0.0);
			set_ad_lifetime_round(ads,0.0);
			set_ad_map(ads,g_sMapName);
			set_ad_precache(ads,add_precache_model(tmpmodelpath));
			set_ad_rotate_speed(ads,0.0);
			set_ad_rotatedir(ads,0);
			set_ad_team(ads,TEAM_UNASSIGNED);
			set_ad_framerate(ads,0.0);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_CREATEAD(id);
			unstuckplayer(id);
			return PLUGIN_HANDLED
		}
		case 4:
		{
			new tmpmodelpath[256];
			precache_get_model(g_iPlayerSelectID[id],tmpmodelpath, charsmax(tmpmodelpath));
			new ads = get_ads_count();
			new Float:vOrigin[3];
			get_entvar(id,var_origin,vOrigin);
			set_ads_count(get_ads_count() + 1);
			set_ad_model(ads,tmpmodelpath);
			set_ad_type(ads,"BSPMODEL_LADDER");
			set_ad_origin(ads,vOrigin);
			set_ad_angles(ads, Float:{0.0,0.0,0.0});
			set_ad_disabled(ads, 0);
			set_ad_lifetime(ads,0.0);
			set_ad_lifetime_round(ads,0.0);
			set_ad_map(ads,g_sMapName);
			set_ad_precache(ads,add_precache_model(tmpmodelpath));
			set_ad_rotate_speed(ads,0.0);
			set_ad_rotatedir(ads,0);
			set_ad_team(ads,TEAM_UNASSIGNED);
			set_ad_framerate(ads,0.0);
			update_all_ads();
			menu_destroy(vmenu)
			MENU_CREATEAD(id);
			unstuckplayer(id);
			return PLUGIN_HANDLED
		}
		case 101:
		{
			g_iSelectedMenu[id]++;
			if (g_iSelectedMenu[id] < 0 || g_iSelectedMenu[id] >= UNREAL_MDL_MAX_MENUS)
			{
				g_iSelectedMenu[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_AD_MENU_SELECT(id);
			return PLUGIN_HANDLED
		}
		case 102:
		{
			g_iPlayerSelectID[id]++;
			if (g_iPlayerSelectID[id] < 0 || g_iPlayerSelectID[id] >= g_iPrecachedModels)
			{
				g_iPlayerSelectID[id] = 0;
			}
			menu_destroy(vmenu)
			MENU_CREATEAD(id);
			return PLUGIN_HANDLED
		}
	}
	menu_destroy(vmenu)
	return PLUGIN_HANDLED
}



public MENU_CREATEAD(id)
{
	if (get_user_flags(id) & UNREAL_MDL_ACCESS_LEVEL)
	{
		if (g_iPrecachedModels == 0)
		{
			client_print_color(id,print_team_red,"НЕТ ДОСТУПНЫХ МОДЕЛЕЙ");
			return;
		}
		
		if (g_iPlayerSelectID[id] < 0 || g_iPlayerSelectID[id] >= g_iPrecachedModels)
		{
			g_iPlayerSelectID[id] = 0;
		}
		
		new tmpmodelpath[256];
		precache_get_model(g_iPlayerSelectID[id],tmpmodelpath, charsmax(tmpmodelpath));

		new tmpmenuitem[256];
		formatex(tmpmenuitem,charsmax(tmpmenuitem),"\rCreate:[\w%s\r]", tmpmodelpath);

		new vmenu = menu_create(tmpmenuitem, "MENU_CREATEAD_HANDLER")
		menu_additem(vmenu, "\wСледующее меню","101")
		menu_additem(vmenu, "\yСледующая модель","102")
		
		formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w[\r%s\w]", "Создать SPRITE");
		menu_additem(vmenu, tmpmenuitem,"1")
		formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w[\r%s\w]", "Создать MODEL");
		menu_additem(vmenu, tmpmenuitem,"2")
		if (containi(tmpmodelpath,".bsp") != -1)
		{
			formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w[\r%s\w]", "Создать BSPMODEL_SOLID");
			menu_additem(vmenu, tmpmenuitem,"3")
			formatex(tmpmenuitem,charsmax(tmpmenuitem),"\w[\r%s\w]", "Создать BSPMODEL_LADDER");
			menu_additem(vmenu, tmpmenuitem,"4")
		}
		
		menu_setprop(vmenu, MPROP_EXITNAME, "\rВыйти из UNREAL AD меню")
		menu_setprop(vmenu, MPROP_EXIT,MEXIT_ALL)


		menu_display(id,vmenu,0)
	}
}

public AddToFullPack_Post(const handle, const e, const ent, const host, const hostflags, const bool:player, const pSet)
{
	if (!player)
	{
		if (is_entity(ent))
		{
			new TeamName:entTeam = (get_entvar(ent, var_iuser3) - UNREAL_MDL_MAGIC_NUMBER);
			if (entTeam != TEAM_UNASSIGNED)
			{
				if (entTeam == TEAM_TERRORIST || entTeam == TEAM_CT ||
					entTeam == TEAM_SPECTATOR)
				{
					if (g_iPlayerTeams[host] != entTeam)
					{
						set_es(handle, ES_Effects, EF_NODRAW);
					}
				}
			}
		}
	}
}

public cache_player_teams(id)
{
	new mPlayers[32];
	new mCount;
	get_players(mPlayers, mCount, "c");
	for(new i = 0; i < mCount;i++)
	{
		if (is_user_hltv(mPlayers[i]))
		{
			g_iPlayerTeams[mPlayers[i]] = TEAM_SPECTATOR;
		}
		else 
		{
			g_iPlayerTeams[mPlayers[i]] = get_member(mPlayers[i], m_iTeam)
		}
	}
}

public CSGameRules_RestartRound_Pre() 
{
	g_fRoundStartTime = get_gametime();
}

public plugin_end()
{
	get_configsdir(g_sAdsPath, charsmax(g_sAdsPath));
	add(g_sAdsPath, charsmax(g_sAdsPath), "/unreal_mdls.json");
	json_serial_to_file(g_jAdsList,g_sAdsPath,true);
	json_free(g_jAdsList);
}

public plugin_precache()
{
	get_configsdir(g_sAdsPath, charsmax(g_sAdsPath));
	add(g_sAdsPath, charsmax(g_sAdsPath), "/unreal_mdls.json");
	
	g_jAdsList = json_parse(g_sAdsPath,true);
	if (g_jAdsList == Invalid_JSON)
	{
		g_jAdsList = json_init_object();
	}
	
	/*
	TESTS STUFF
	if (get_ads_count() == 0)
	{
		set_ads_count(1);
		set_ad_model(0,"models/player/gign/gign.mdl");
		set_ad_type(0,"MODEL");
		
		new pEnt = MaxClients;
		new Float:vOrigin[3]
		while( ( pEnt = rg_find_ent_by_class( pEnt, "info_player_start", .useHashTable = false ) ) )
		{
			get_entvar( pEnt, var_origin, vOrigin );
			break;
		}
		//set_ad_lifetime_round(0,5.0);
		//set_ad_origin(0,vOrigin);
		//set_ad_rotate_speed(0,0.5);
		//set_ad_rotatedir(0,1);
		set_ad_team(0,TEAM_TERRORIST);
	}*/
	
	// Precache all models used in ads
	new a_cnt = get_ads_count() - 1;
	for(;a_cnt >= 0;)
	{
		if (get_ad_disabled(a_cnt) == 0)
		{
			new a_model[256];
			get_ad_model(a_cnt,a_model,charsmax(a_model));
			if (file_exists(a_model))
			{
				set_ad_precache(a_cnt,add_precache_model(a_model));
			}
			else 
			{
				set_ad_precache(a_cnt, -1)
			}
		}
		else 
			set_ad_precache(a_cnt, -1)
		a_cnt--;
	}
	
	// Precache all models from directory models/unreal_mdls/
	new fileName[ 64 ];
	new handleDir = open_dir( UNREAL_MDLS_DIRECTORY, fileName, charsmax( fileName ) );
	if ( handleDir )
	{
		do
		{
			if(containi(fileName, ".mdl") == -1 && containi(fileName, ".spr") == -1
				&& containi(fileName, ".bsp") == -1)
			{
				continue;
			}
			
			if(containi(fileName, ".ztmp") != -1)
			{
				continue;
			}
			new a_model[256];
			formatex(a_model,charsmax(a_model),"models/unreal_mdls/%s",fileName);
			add_precache_model(a_model);
		}   
		while ( next_file( handleDir, fileName, charsmax( fileName ) ) );
		close_dir( handleDir );
	}
	
	server_print("[%s] Loaded %d objects and %d models.",PLUGIN,get_ads_count(),g_iPrecachedModels);
	log_amx("[%s] Loaded %d objects and %d models.",PLUGIN,get_ads_count(),g_iPrecachedModels);
}


public remove_all_ads()
{
	new pEnt = MaxClients;
	
	while( ( pEnt = rg_find_ent_by_class( pEnt, UNREAL_MDLS_CUSTOM_CLASSNAME, .useHashTable = false ) ) )
	{
		set_entvar( pEnt, var_flags, FL_KILLME );
		set_entvar( pEnt, var_nextthink, get_gametime())
	}
}

rg_set_ent_rendering(const index, fx = kRenderFxNone, {Float,_}:color[3] = {0.0,0.0,0.0}, render = kRenderNormal, Float:amount = 0.0)
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
	new pEnt = 0;

	new sModelType[256];
	get_ad_type(id,sModelType,charsmax(sModelType));
	
	if (equal(sModelType,"BSPMODEL_SOLID"))
	{
		pEnt = rg_create_entity( "func_rotating", .useHashTable = false );
	}
	else if (equal(sModelType,"BSPMODEL_LADDER"))
	{
		pEnt = rg_create_entity( "func_rotating", .useHashTable = false );
	}
	else 
	{
		pEnt = rg_create_entity( "info_target", .useHashTable = false );
	}
	if( !pEnt )
	{
		return;
	}
	
	new sModelPath[256];
	get_ad_model(id,sModelPath,charsmax(sModelPath));
	
	new Float:vOrigin[3];
	get_ad_origin(id,vOrigin);
	new Float:vAngles[3];
	get_ad_angles(id,vAngles);
	set_entvar( pEnt, var_nextthink, get_gametime( ) );
	set_entvar( pEnt, var_origin, vOrigin );
	set_entvar( pEnt, var_angles, vAngles );
	set_entvar( pEnt, var_iuser1, id);
	set_entvar( pEnt, var_iuser2, get_ad_rotatedir(id));
	set_entvar( pEnt, var_iuser3, get_ad_team(id) + UNREAL_MDL_MAGIC_NUMBER);
	set_entvar( pEnt, var_animtime, get_gametime( ) );
	set_entvar( pEnt, var_scale, 1.0);
	
	set_entvar( pEnt, var_model, sModelPath);
	set_entvar( pEnt, var_modelindex, pPrecacheId);
	set_entvar( pEnt, var_framerate, get_ad_framerate(id));
	set_entvar( pEnt, var_iuser1, engfunc(EngFunc_ModelFrames, pPrecacheId) - 1);

	new Float:vUserData[3]; 
	vUserData[0] = get_ad_lifetime(id);
	vUserData[1] = get_ad_lifetime_round(id);
	vUserData[2] = get_ad_rotate_speed(id);
	
	set_entvar( pEnt, var_vuser1, vUserData);
	
	
	if (equal(sModelType,"SPRITE"))
	{
		set_entvar( pEnt, var_takedamage, 0.0);
		set_entvar( pEnt, var_solid, SOLID_NOT);
		set_entvar( pEnt, var_movetype, MOVETYPE_NONE);
		rg_set_ent_rendering(pEnt, kRenderFxNoDissipation, Float:{255.0,255.0,255.0}, kRenderTransAdd, 255.0);
		SetThink( pEnt, "AD_THINK_SPRITE" );
	}
	else if (equal(sModelType,"BSPMODEL_SOLID"))
	{
		set_entvar( pEnt, var_solid, SOLID_BSP);
		set_entvar( pEnt, var_movetype, MOVETYPE_PUSH);
		set_entvar( pEnt, var_skin, CONTENTS_SOLID);
		dllfunc( DLLFunc_Spawn, pEnt);
		SetThink( pEnt, "AD_THINK" );
	}
	else if (equal(sModelType,"BSPMODEL_LADDER"))
	{
		rg_set_ent_rendering(pEnt, kRenderFxNone, Float:{255.0,255.0,255.0}, kRenderTransTexture, 255.0);
		set_entvar( pEnt, var_solid, SOLID_BSP);
		set_entvar( pEnt, var_movetype, MOVETYPE_PUSH);
		set_entvar( pEnt, var_skin, CONTENTS_SOLID);
		dllfunc( DLLFunc_Spawn, pEnt);
		SetThink( pEnt, "AD_THINK" );
		SetTouch(pEnt, "AD_TOUCH_LADDER");
	}
	else 
	{
		set_entvar( pEnt, var_takedamage, 0.0);
		set_entvar( pEnt, var_solid, SOLID_NOT);
		set_entvar( pEnt, var_movetype, MOVETYPE_NONE);
		SetThink( pEnt, "AD_THINK" );
	}
	set_entvar( pEnt, var_classname, UNREAL_MDLS_CUSTOM_CLASSNAME );
}

public reset_velocity(idx)
{
	new other = idx - 5000;
	set_entvar(other, var_basevelocity,Float:{0.0,0.0,0.0});
	set_entvar(other, var_velocity,Float:{0.0,0.0,0.0});
	if (task_exists(4000+other))
	{
		remove_task(4000+other);
	}
}

public set_velocity(idx)
{
	new other = idx - 4000;
	new Float:vOrigin[3];
	get_entvar(other,var_origin,vOrigin);
	vOrigin[2] += 5.0;
	set_entvar(other,var_origin,vOrigin);
}

public AD_TOUCH_LADDER(const ent, const other)
{
	if (other > 0 && other < 33)
	{
		set_entvar(other,var_basevelocity,Float:{0.0,0.0,20.0});
		if (task_exists(5000+other))
		{
			remove_task(5000+other);
		}
		set_task_ex(0.1, "reset_velocity", .id = 5000+other);
		if (!task_exists(4000+other))
		{
			set_task_ex(0.2, "set_velocity", .id = 4000+other,.flags = SetTask_Repeat);
		}
	}
}

public AD_THINK( const pEnt )
{
	if( !is_entity( pEnt ) )
		return;
	AD_THINK_WORKER(pEnt);
}

public AD_THINK_SPRITE( const pEnt )
{
	if( !is_entity( pEnt ) )
		return;
	
	new Float:fFrameRate = get_entvar(pEnt,var_framerate);
	new iMaxFrames = get_entvar(pEnt,var_iuser1);
	if (fFrameRate != 0.0 && iMaxFrames > 0)
	{
		new Float:fFrame = get_entvar(pEnt,var_frame);
		new Float:fIncr = fFrameRate * 0.05;
		if (fFrame > iMaxFrames)
			fFrame = 0.0;
		set_entvar(pEnt,var_frame,fFrame + fIncr);
	}
	AD_THINK_WORKER(pEnt);
}

public AD_THINK_WORKER( const pEnt )
{
	new Float:vUserData[3];
	get_entvar(pEnt,var_vuser1,vUserData);
		
	new Float:fLife = vUserData[0];
	new Float:fLifeRound = vUserData[1];
	new Float:fRotateSpeed = vUserData[2];
	
	new iRotateDir = get_entvar(pEnt,var_iuser2);
	
	if (iRotateDir > 0)
	{
		iRotateDir--;
		new Float:vAngles[3];
		get_entvar(pEnt,var_angles,vAngles);
		if (iRotateDir > 2)
		{
			switch(iRotateDir)
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
		set_entvar(pEnt,var_angles,vAngles);
	}
	
	if (fLife != 0.0 && fLife < get_gametime() - g_fMapStartTime)
	{
		set_entvar( pEnt, var_flags, FL_KILLME );
	}
	else 
	{
		if (fLifeRound != 0.0)
		{
			if (fLifeRound < get_gametime() - g_fRoundStartTime)
			{
				if ( !( get_entvar(pEnt, var_effects) & EF_NODRAW ) )
				{
					set_entvar(pEnt, var_effects, get_entvar(pEnt, var_effects) + EF_NODRAW );
				}
			}
			else 
			{
				if ( get_entvar(pEnt, var_effects) & EF_NODRAW )
				{
					set_entvar(pEnt, var_effects, get_entvar(pEnt, var_effects) - EF_NODRAW );
				}
			}
		}

		set_entvar( pEnt, var_nextthink, get_gametime( ) + 0.05 );
	}
}

public create_all_ads()
{
	new a_cnt = get_ads_count() - 1;
	for(;a_cnt >= 0;)
	{
		new a_map[64];
		get_ad_map(a_cnt,a_map,charsmax(a_map));
		if (get_ad_disabled(a_cnt) == 0 && equal(a_map,g_sMapName))
		{
			create_one_ad(a_cnt)
		}
		a_cnt--;
	}
}

public update_all_ads()
{
	remove_all_ads();
	create_all_ads();
}

public get_ads_count()
{
	return json_object_get_number(g_jAdsList,"ADS_NUM");
}

public set_ads_count(count)
{
	json_object_set_number(g_jAdsList,"ADS_NUM",count);
}

new static_ad_type[64];
public get_ad_type(id, str[],len)
{
	formatex(static_ad_type,charsmax(static_ad_type),"%d_TYPE",id)
	json_object_get_string(g_jAdsList,static_ad_type,str,len);
}

public set_ad_type(id, str[])
{
	formatex(static_ad_type,charsmax(static_ad_type),"%d_TYPE",id)
	json_object_set_string(g_jAdsList,static_ad_type,str);
}

new static_ad_model[256];
public get_ad_model(id, str[],len)
{
	formatex(static_ad_model,charsmax(static_ad_model),"%d_MODEL",id)
	json_object_get_string(g_jAdsList,static_ad_model,str,len);
}

public set_ad_model(id, str[])
{
	formatex(static_ad_model,charsmax(static_ad_model),"%d_MODEL",id)
	json_object_set_string(g_jAdsList,static_ad_model,str);
}

new static_ad_map[64];
public get_ad_map(id, str[],len)
{
	formatex(static_ad_map,charsmax(static_ad_map),"%d_MAP",id)
	json_object_get_string(g_jAdsList,static_ad_map,str,len);
}

public set_ad_map(id, str[])
{
	formatex(static_ad_map,charsmax(static_ad_map),"%d_MAP",id)
	json_object_set_string(g_jAdsList,static_ad_map,str);
}

new static_ad_precache[64];
public get_ad_precache(id)
{
	formatex(static_ad_precache,charsmax(static_ad_precache),"%d_precacheId",id)
	return json_object_get_number(g_jAdsList,static_ad_precache);
}

public set_ad_precache(id, precacheId)
{
	formatex(static_ad_precache,charsmax(static_ad_precache),"%d_precacheId",id)
	json_object_set_number(g_jAdsList,static_ad_precache,precacheId);
}

new static_ad_disabled[64];
public get_ad_disabled(id)
{
	formatex(static_ad_disabled,charsmax(static_ad_disabled),"%d_disabled",id)
	return json_object_get_number(g_jAdsList,static_ad_disabled);
}

public set_ad_disabled(id, disabled)
{
	formatex(static_ad_disabled,charsmax(static_ad_disabled),"%d_disabled",id)
	json_object_set_number(g_jAdsList,static_ad_disabled,disabled);
}

new static_ad_rotatedir[64];
public get_ad_rotatedir(id)
{
	formatex(static_ad_rotatedir,charsmax(static_ad_rotatedir),"%d_rotatedir",id)
	return json_object_get_number(g_jAdsList,static_ad_rotatedir);
}

public set_ad_rotatedir(id, rotatedir)
{
	formatex(static_ad_rotatedir,charsmax(static_ad_rotatedir),"%d_rotatedir",id)
	json_object_set_number(g_jAdsList,static_ad_rotatedir,rotatedir);
}


new static_ad_team[64];
public get_ad_team(id)
{
	formatex(static_ad_team,charsmax(static_ad_team),"%d_team",id)
	return json_object_get_number(g_jAdsList,static_ad_team);
}

public set_ad_team(id, TeamName:team)
{
	formatex(static_ad_team,charsmax(static_ad_team),"%d_team",id)
	json_object_set_number(g_jAdsList,static_ad_team, cell:team);
}

new static_ad_lifetime[64];
public Float:get_ad_lifetime(id)
{
	formatex(static_ad_lifetime,charsmax(static_ad_lifetime),"%d_lifetime",id)
	return json_object_get_real(g_jAdsList,static_ad_lifetime);
}

public set_ad_lifetime(id, Float:lifetime)
{
	formatex(static_ad_lifetime,charsmax(static_ad_lifetime),"%d_lifetime",id)
	json_object_set_real(g_jAdsList,static_ad_lifetime,lifetime);
}


new static_ad_framerate[64];
public Float:get_ad_framerate(id)
{
	formatex(static_ad_framerate,charsmax(static_ad_framerate),"%d_framerate",id)
	return json_object_get_real(g_jAdsList,static_ad_framerate);
}

public set_ad_framerate(id, Float:framerate)
{
	formatex(static_ad_framerate,charsmax(static_ad_framerate),"%d_framerate",id)
	json_object_set_real(g_jAdsList,static_ad_framerate,framerate);
}

new static_ad_rotate_speed[64];
public Float:get_ad_rotate_speed(id)
{
	formatex(static_ad_rotate_speed,charsmax(static_ad_rotate_speed),"%d_rotate_speed",id)
	return json_object_get_real(g_jAdsList,static_ad_rotate_speed);
}

public set_ad_rotate_speed(id, Float:rotspeed)
{
	formatex(static_ad_rotate_speed,charsmax(static_ad_rotate_speed),"%d_rotate_speed",id)
	json_object_set_real(g_jAdsList,static_ad_rotate_speed,rotspeed);
}


new static_ad_lifetime_round[64];
public Float:get_ad_lifetime_round(id)
{
	formatex(static_ad_lifetime_round,charsmax(static_ad_lifetime_round),"%d_lifetime_round",id)
	return json_object_get_real(g_jAdsList,static_ad_lifetime_round);
}

public set_ad_lifetime_round(id, Float:lifetime)
{
	formatex(static_ad_lifetime_round,charsmax(static_ad_lifetime_round),"%d_lifetime_round",id)
	json_object_set_real(g_jAdsList,static_ad_lifetime_round,lifetime);
}


new static_ad_origin[64];
public get_ad_origin(id, Float:origin[3])
{
	formatex(static_ad_origin,charsmax(static_ad_origin),"%d_origin_x",id)
	origin[0] = json_object_get_real(g_jAdsList,static_ad_origin);
	formatex(static_ad_origin,charsmax(static_ad_origin),"%d_origin_y",id)
	origin[1] = json_object_get_real(g_jAdsList,static_ad_origin);
	formatex(static_ad_origin,charsmax(static_ad_origin),"%d_origin_z",id)
	origin[2] = json_object_get_real(g_jAdsList,static_ad_origin);
}

public set_ad_origin(id, Float:origin[3])
{
	formatex(static_ad_origin,charsmax(static_ad_origin),"%d_origin_x",id)
	json_object_set_real(g_jAdsList,static_ad_origin,origin[0]);
	formatex(static_ad_origin,charsmax(static_ad_origin),"%d_origin_y",id)
	json_object_set_real(g_jAdsList,static_ad_origin,origin[1]);
	formatex(static_ad_origin,charsmax(static_ad_origin),"%d_origin_z",id)
	json_object_set_real(g_jAdsList,static_ad_origin,origin[2]);
}

new static_ad_angles[64];
public get_ad_angles(id, Float:angles[3])
{
	formatex(static_ad_angles,charsmax(static_ad_angles),"%d_angles_x",id)
	angles[0] = json_object_get_real(g_jAdsList,static_ad_angles);
	formatex(static_ad_angles,charsmax(static_ad_angles),"%d_angles_y",id)
	angles[1] = json_object_get_real(g_jAdsList,static_ad_angles);
	formatex(static_ad_angles,charsmax(static_ad_angles),"%d_angles_z",id)
	angles[2] = json_object_get_real(g_jAdsList,static_ad_angles);
}

public set_ad_angles(id, Float:angles[3])
{
	formatex(static_ad_angles,charsmax(static_ad_angles),"%d_angles_x",id)
	json_object_set_real(g_jAdsList,static_ad_angles,angles[0]);
	formatex(static_ad_angles,charsmax(static_ad_angles),"%d_angles_y",id)
	json_object_set_real(g_jAdsList,static_ad_angles,angles[1]);
	formatex(static_ad_angles,charsmax(static_ad_angles),"%d_angles_z",id)
	json_object_set_real(g_jAdsList,static_ad_angles,angles[2]);
}


new static_precache_name[64];
new static_precache_id[64];
new static_precache_path[256];
public add_precache_model(mdl[])
{
	new return_value = 0;
	for(new i = g_iPrecachedModels - 1;i >= 0;)
	{
		formatex(static_precache_name,charsmax(static_precache_name),"MDL_%d_precachePath",i)
		formatex(static_precache_id,charsmax(static_precache_id),"MDL_%d_precacheId",i)
		json_object_get_string(g_jAdsList,static_precache_name,static_precache_path,charsmax(static_precache_path));
		if (equal(mdl,static_precache_path))
			return json_object_get_number(g_jAdsList,static_precache_id)
		i--;
	}
	
	formatex(static_precache_name,charsmax(static_precache_name),"MDL_%d_precachePath",g_iPrecachedModels)
	formatex(static_precache_id,charsmax(static_precache_id),"MDL_%d_precacheId",g_iPrecachedModels)
	
	return_value = precache_model(mdl);
	
	json_object_set_string(g_jAdsList,static_precache_name,mdl);
	json_object_set_number(g_jAdsList,static_precache_id,return_value);
	
	g_iPrecachedModels++;
	return return_value;
}

public precache_get_model(id,str[],len)
{
	formatex(static_precache_name,charsmax(static_precache_name),"MDL_%d_precachePath",id)
	json_object_get_string(g_jAdsList,static_precache_name,str,len);
}



/* UNSTUCK STUFF */
#define TSC_Vector_MA(%1,%2,%3,%4)	(%4[0] = %2[0] * %3 + %1[0], %4[1] = %2[1] * %3 + %1[1])

stock is_player_stuck(id,Float:originF[3])
{
	engfunc(EngFunc_TraceHull, originF, originF, 0, (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN, id, 0)
	
	if (get_tr2(0, TR_StartSolid) || get_tr2(0, TR_AllSolid) || !get_tr2(0, TR_InOpen))
		return true
	
	return false
}


stock is_hull_vacant(Float:origin[3], hull)
{
	engfunc(EngFunc_TraceHull, origin, origin, DONT_IGNORE_MONSTERS, hull, 0, 0)
	
	if (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen))
		return true
	
	return false
}

public unstuckplayer(id)
{
	static Float:Origin[3]
	pev(id, pev_origin, Origin)
	static iHull, iSpawnPoint, i
	iHull = (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN
	
	// fast unstuck 
	if(is_player_stuck(id,Origin))
	{
		Origin[2] -= 64.0
	}
	else
	{
		engfunc(EngFunc_SetOrigin, id, Origin)	
		return;
	}
	if(is_player_stuck(id,Origin))
	{
		Origin[2] += 128.0
	}
	else
	{
		engfunc(EngFunc_SetOrigin, id, Origin)	
		return;
	}
	
	// slow unstuck 
	if(is_player_stuck(id,Origin))
	{
		static const Float:RANDOM_OWN_PLACE[][3] =
		{
			{ -96.5,   0.0, 0.0 },
			{  96.5,   0.0, 0.0 },
			{   0.0, -96.5, 0.0 },
			{   0.0,  96.5, 0.0 },
			{ -96.5, -96.5, 0.0 },
			{ -96.5,  96.5, 0.0 },
			{  96.5,  96.5, 0.0 },
			{  96.5, -96.5, 0.0 }
		}
		
		new Float:flOrigin[3], Float:flOriginFinal[3], iSize
		pev(id, pev_origin, flOrigin)
		iSize = sizeof(RANDOM_OWN_PLACE)
		
		iSpawnPoint = random_num(0, iSize - 1)
		
		for (i = iSpawnPoint + 1; /*no condition*/; i++)
		{
			if (i >= iSize)
				i = 0
			
			flOriginFinal[0] = flOrigin[0] + RANDOM_OWN_PLACE[i][0]
			flOriginFinal[1] = flOrigin[1] + RANDOM_OWN_PLACE[i][1]
			flOriginFinal[2] = flOrigin[2]
			
			engfunc(EngFunc_TraceLine, flOrigin, flOriginFinal, IGNORE_MONSTERS, id, 0)
			
			new Float:flFraction
			get_tr2(0, TR_flFraction, flFraction)
			if (flFraction < 1.0)
			{
				new Float:vTraceEnd[3], Float:vNormal[3]
				get_tr2(0, TR_vecEndPos, vTraceEnd)
				get_tr2(0, TR_vecPlaneNormal, vNormal)
				
				TSC_Vector_MA(vTraceEnd, vNormal, 32.5, flOriginFinal)
			}
			flOriginFinal[2] -= 35.0
			
			new iZ = 0
			do
			{
				if (is_hull_vacant(flOriginFinal, iHull))
				{
					i = iSpawnPoint
					engfunc(EngFunc_SetOrigin, id, flOriginFinal)
					break
				}
				
				flOriginFinal[2] += 40.0
			}
			while (++iZ <= 2)
			
			if (i == iSpawnPoint)
				break
		}
	}
	else
	{
		engfunc(EngFunc_SetOrigin, id, Origin)	
	}
}