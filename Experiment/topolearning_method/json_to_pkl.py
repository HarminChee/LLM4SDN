
import os
import json
import pickle
import toponetx as tnx
from json import JSONDecodeError

######################################################
# 1) 工具函数：大小写统一
######################################################
def normalize_id(name):
    """
    将出现的节点名称统一转换为小写，
    并去除可能的空格。
    """
    return str(name).strip().lower()

######################################################
# 2) 判断 router / switch
######################################################
def is_router(node_id, node_info):
    """判断 node 是否 router"""
    if not isinstance(node_info, dict):
        return False
    if node_info.get("type") == "router":
        return True
    lower_id = node_id.lower()
    if lower_id.startswith("r"):
        return True
    return False

def is_switch(node_id, node_info):
    """判断 node 是否 switch"""
    if not isinstance(node_info, dict):
        return False
    if node_info.get("type") == "switch":
        return True
    lower_id = node_id.lower()
    if lower_id.startswith("sw"):
        return True
    return False

######################################################
# 3) 提取 router/switch/link
######################################################
def process_router(r_id, r_info):
    """
    提取常见字段: interfaces, bgp, ospf, ...
    并保留其它字段到 router_dict
    """
    router_dict = {}
    router_dict["type"] = "router"

    # interfaces
    router_dict["interfaces"] = extract_interfaces(r_info)

    if "bgp" in r_info:
        router_dict["bgp"] = r_info["bgp"]
    if "ospf" in r_info:
        router_dict["ospf"] = r_info["ospf"]
    if "route_maps" in r_info:
        router_dict["route_maps"] = r_info["route_maps"]
    if "static_routes" in r_info:
        router_dict["static_routes"] = r_info["static_routes"]
    if "isis" in r_info:
        router_dict["isis"] = r_info["isis"]
    if "babel" in r_info:
        router_dict["babel"] = r_info["babel"]

    known_keys = {
        "interfaces", "bgp", "ospf", "route_maps",
        "static_routes", "type", "isis", "babel"
    }
    for k, v in r_info.items():
        if k not in known_keys:
            router_dict[k] = v

    return router_dict

def extract_interfaces(r_info):
    """
    统一将 r_info["interfaces"] 转成 dict{ interface_name: {...} }
    """
    interfaces_dict = {}
    if "interfaces" in r_info:
        if isinstance(r_info["interfaces"], dict):
            for itf_name, itf_detail in r_info["interfaces"].items():
                if isinstance(itf_detail, dict):
                    interfaces_dict[itf_name] = itf_detail
                else:
                    interfaces_dict[itf_name] = {"raw": itf_detail}
        elif isinstance(r_info["interfaces"], list):
            for itf_item in r_info["interfaces"]:
                if isinstance(itf_item, dict):
                    name = itf_item.get("interface","unknown")
                    interfaces_dict[name] = itf_item
                else:
                    interfaces_dict[str(itf_item)] = {}
    return interfaces_dict

def process_switch(s_id, sw_info):
    switch_dict = {}
    switch_dict["type"] = "switch"

    if "connected_devices" in sw_info:
        switch_dict["connected_devices"] = sw_info["connected_devices"]
    if "connected_nodes" in sw_info:
        switch_dict["connected_nodes"] = sw_info["connected_nodes"]
    if "subnet" in sw_info:
        switch_dict["subnet"] = sw_info["subnet"]
    if "description" in sw_info:
        switch_dict["description"] = sw_info["description"]

    known_keys = {"type","connected_devices","connected_nodes","subnet","description"}
    for k,v in sw_info.items():
        if k not in known_keys:
            switch_dict[k] = v

    return switch_dict

def process_link(link_item):
    """
    link_item => { "source":"...", "target":"...", "bandwidth":"...", ... }
    """
    source = link_item.get("source")
    target = link_item.get("target")
    if not source or not target:
        return None

    source_norm = normalize_id(source)
    target_norm = normalize_id(target)

    new_link = {"source": source_norm, "target": target_norm}

    link_props = link_item.get("link_properties", {})
    if isinstance(link_props, dict):
        if "bandwidth" in link_props:
            new_link["bandwidth"] = link_props["bandwidth"]
        if "latency" in link_props:
            new_link["latency"] = link_props["latency"]
    else:
        if "bandwidth" in link_item:
            new_link["bandwidth"] = link_item["bandwidth"]
        if "latency" in link_item:
            new_link["latency"] = link_item["latency"]

    known_keys = {"source","target","link_properties","bandwidth","latency"}
    for k,v in link_item.items():
        if k not in known_keys:
            new_link[k] = v

    return new_link

######################################################
# 4) enrich_* (给 router/switch/link 加更多属性)
######################################################
def parse_ipv4_to_numeric(ip_str):
    core_ip = ip_str.split("/")[0] if "/" in ip_str else ip_str
    segs = core_ip.split(".")
    if len(segs) != 4:
        return 0
    val = 0
    for s in segs:
        try:
            part = int(s)
        except:
            part = 0
        val = (val << 8) + (part & 0xFF)
    return val

def enrich_router_attributes(r_id, router_data):
    """
    在这里添加更多特征统计，如：
    - bgp_local_as
    - ospf_area
    - interfaces_count
    - vendor
    - hostname
    - number_of_bgp_neighbors
    - number_of_bgp_networks
    - number_of_route_maps
    - number_of_static_routes
    - number_of_isis/babel/bfd sessions (若有)
    """
    attrs = {}
    attrs["type"] = "router"

    # 1) BGP
    local_as = None
    bgp_neighbor_count = 0
    bgp_network_count = 0
    route_map_count = 0

    bgp_data = router_data.get("bgp", {})
    if isinstance(bgp_data, dict):
        # local_as
        las = bgp_data.get("local_as")
        if las:
            try:
                local_as = int(las)
            except:
                local_as = None

        # BGP neighbors
        neighbors = bgp_data.get("neighbors", {})
        if isinstance(neighbors, dict):
            bgp_neighbor_count = len(neighbors)

        if "networks" in bgp_data and isinstance(bgp_data["networks"], list):
            bgp_network_count = len(bgp_data["networks"])

    # 2) OSPF
    ospf_area = None
    ospf_data = router_data.get("ospf", {})
    if isinstance(ospf_data, dict):
        area = ospf_data.get("area")
        try:
            ospf_area = int(area)
        except:
            ospf_area = None

    # 3) Interfaces
    interface_dict = router_data.get("interfaces", {})
    interfaces_count = len(interface_dict) if isinstance(interface_dict, dict) else 0

    # 4) vendor / hostname
    vendor_str = str(router_data.get("vendor", "")).lower()
    hostname   = str(router_data.get("hostname", "")).lower()

    # 5) route_maps
    if "route_maps" in router_data and isinstance(router_data["route_maps"], dict):
        route_map_count = len(router_data["route_maps"])

    # 6) static routes
    static_rt_count = 0
    if "static_routes" in router_data and isinstance(router_data["static_routes"], list):
        static_rt_count = len(router_data["static_routes"])

    # 7) isis / babel / bfd ...
    isis_data = router_data.get("isis", {})
    if isinstance(isis_data, dict):
        pass  

    babel_data = router_data.get("babel", {})
    if isinstance(babel_data, dict):
        pass  

    # 8) 
    attrs["bgp_local_as"] = local_as if local_as else 0
    attrs["bgp_neighbor_count"] = bgp_neighbor_count
    attrs["bgp_network_count"] = bgp_network_count

    attrs["ospf_area"] = ospf_area if ospf_area else 0
    attrs["interfaces_count"] = interfaces_count
    attrs["vendor"] = vendor_str
    attrs["hostname"] = hostname
    attrs["route_map_count"] = route_map_count
    attrs["static_rt_count"] = static_rt_count
    
    print(f"[DEBUG-enrich] r_id={r_id}, local_as={local_as}, "
          f"bgp_neighbor_count={bgp_neighbor_count}, "
          f"bgp_network_count={bgp_network_count}, "
          f"route_map_count={route_map_count}, "
          f"static_rt_count={static_rt_count}")
    attrs["full_data"] = router_data
    return attrs

def enrich_switch_attributes(s_id, switch_data):
    attrs = {}
    attrs["type"] = "switch"

    c_nodes = switch_data.get("connected_nodes", [])
    if isinstance(c_nodes, list):
        attrs["connected_nodes_count"] = len(c_nodes)
    else:
        attrs["connected_nodes_count"] = 0

    if "vendor" in switch_data:
        attrs["vendor"] = switch_data["vendor"]
    if "hostname" in switch_data:
        attrs["hostname"] = switch_data["hostname"]

    attrs["full_data"] = switch_data
    return attrs

def enrich_link_attributes(link_data):
    attrs = {}

    if "bandwidth" in link_data:
        attrs["bandwidth"] = link_data["bandwidth"]
    if "latency" in link_data:
        attrs["latency"] = link_data["latency"]

    if "ipv4" in link_data:
        ip_val = parse_ipv4_to_numeric(link_data["ipv4"])
        attrs["ipv4_parsed"] = ip_val
    if "ipv6" in link_data:
        attrs["ipv6"] = link_data["ipv6"]

    for key in ["cost","as_number","route_map","ospf_area","priority"]:
        if key in link_data:
            attrs[key] = link_data[key]

    attrs["full_data"] = link_data
    return attrs

######################################################
# 5) 统一 JSON => 构建 SC => pkl
######################################################
def unify_json_structure(original_data):
    """
    将各种格式不统一的网络 JSON 转化为较统一的结构:
    {
      "routers": { "r1": {...}, "r2": {...} },
      "switches": { "sw1": {...}, ... },
      "links": [ { "source":..., "target":..., ...}, ... ],
      "metadata": {}
    }
    """
    unified_data = {
        "routers": {},
        "switches": {},
        "links": [],
        "metadata": {}
    }

    # (0) 提取部分metadata
    for meta_key in [
        "ipv4base", "ipv4mask", "ipv6base", "ipv6mask",
        "link_ip_start", "lo_prefix", "address_types"
    ]:
        if meta_key in original_data:
            unified_data["metadata"][meta_key] = original_data[meta_key]

    # (1) 解析 routers
    if "routers" in original_data and isinstance(original_data["routers"], dict):
        for r_id, r_info in original_data["routers"].items():
            if not isinstance(r_info, dict):
                continue
            unified_data["routers"][r_id] = process_router(r_id, r_info)
    elif ("nodes" in original_data
          and "routers" in original_data["nodes"]
          and isinstance(original_data["nodes"]["routers"], list)):
        for router_item in original_data["nodes"]["routers"]:
            if not isinstance(router_item, dict):
                continue
            r_id = router_item.get("id")
            if r_id:
                unified_data["routers"][r_id] = process_router(r_id, router_item)
    elif ("nodes" in original_data and isinstance(original_data["nodes"], dict)):
        for possible_r_id, r_info in original_data["nodes"].items():
            if is_router(possible_r_id, r_info):
                if isinstance(r_info, dict):
                    unified_data["routers"][possible_r_id] = process_router(possible_r_id, r_info)

    # (2) 解析 switches
    if "switches" in original_data and isinstance(original_data["switches"], dict):
        for sw_id, sw_info in original_data["switches"].items():
            if not isinstance(sw_info, dict):
                continue
            unified_data["switches"][sw_id] = process_switch(sw_id, sw_info)
    elif "switches" in original_data and isinstance(original_data["switches"], list):
        for sw_item in original_data["switches"]:
            if not isinstance(sw_item, dict):
                continue
            s_id = sw_item.get("id")
            if s_id:
                unified_data["switches"][s_id] = process_switch(s_id, sw_item)
    elif ("nodes" in original_data
          and "switches" in original_data["nodes"]
          and isinstance(original_data["nodes"]["switches"], list)):
        for sw_item in original_data["nodes"]["switches"]:
            if not isinstance(sw_item, dict):
                continue
            s_id = sw_item.get("id")
            if s_id:
                unified_data["switches"][s_id] = process_switch(s_id, sw_item)
    elif ("nodes" in original_data and isinstance(original_data["nodes"], dict)):
        for possible_sw_id, sw_info in original_data["nodes"].items():
            if is_switch(possible_sw_id, sw_info):
                if isinstance(sw_info, dict):
                    unified_data["switches"][possible_sw_id] = process_switch(possible_sw_id, sw_info)

    # (3) 解析 links
    if "links" in original_data and isinstance(original_data["links"], list):
        for link_item in original_data["links"]:
            if not isinstance(link_item, dict):
                continue
            link_obj = process_link(link_item)
            if link_obj:
                unified_data["links"].append(link_obj)

    return unified_data

######################################################
# 6) JSON -> SC -> PKL
######################################################
def process_one_json_and_pickle(input_json, output_pkl):
    original_data = try_load_json_strict_or_skip(input_json)
    if original_data is None:
        return 

    unified_data = unify_json_structure(original_data)
    if (not unified_data["routers"]
        and not unified_data["switches"]
        and not unified_data["links"]
        and not unified_data["metadata"]):
        print(f"[INFO] unify后数据为空 => 跳过: {input_json}")
        return

    sc = tnx.SimplicialComplex()

    # (a) routers => rank=0
    for r_id, r_info in unified_data["routers"].items():
        r_id_norm = normalize_id(r_id)
        node_attrs = enrich_router_attributes(r_id_norm, r_info)
        sc.add_simplex([r_id_norm], data=node_attrs)

    # (b) switches => rank=0
    for sw_id, sw_info in unified_data["switches"].items():
        sw_id_norm = normalize_id(sw_id)
        node_attrs = enrich_switch_attributes(sw_id_norm, sw_info)
        sc.add_simplex([sw_id_norm], data=node_attrs)

    # (c) links => rank=1
    for link_item in unified_data["links"]:
        src_raw = link_item.get("source")
        tgt_raw = link_item.get("target")
        if not src_raw or not tgt_raw:
            continue

        src = normalize_id(src_raw)
        tgt = normalize_id(tgt_raw)

        if src not in sc:
            sc.add_simplex([src])
        if tgt not in sc:
            sc.add_simplex([tgt])

        edge_tuple = tuple(sorted([src, tgt]))
        edge_attrs = enrich_link_attributes(link_item)
        sc.add_simplex(edge_tuple, data=edge_attrs)

    # (d) 元数据
    if "metadata" in unified_data and isinstance(unified_data["metadata"], dict):
        sc.metadata = unified_data["metadata"]

    with open(output_pkl, "wb") as ff:
        pickle.dump(sc, ff)
    print(f"[OK] {input_json} => {output_pkl}")

######################################################
# 尝试用 strict JSON 解析，如失败，则跳过
######################################################
def try_load_json_strict_or_skip(file_path):
    """
    先尝试标准 json.load()，若失败则直接跳过。
    如需更多“自动修复”逻辑，可在此扩展。
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except JSONDecodeError as e:
        print(f"[ERROR] 无法解析 {file_path} => {e}")
        return None
    except Exception as e2:
        print(f"[ERROR] 读取文件出现异常 {file_path} => {e2}")
        return None

######################################################
# 7) 批量处理
######################################################
def bulk_process_json_to_pkl(input_dir, output_dir):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    for file_name in os.listdir(input_dir):
        if file_name.lower().endswith(".json"):
            input_json = os.path.join(input_dir, file_name)
            output_pkl = os.path.join(output_dir, file_name.replace(".json", ".pkl"))
            process_one_json_and_pickle(input_json, output_pkl)

######################################################
# main
######################################################
if __name__ == "__main__":
    input_dir = r"C:\Users\harmi\Desktop\sdn\json_for_pkl_new"
    output_dir = r"C:\Users\harmi\Desktop\sdn\cc_pickles"

    bulk_process_json_to_pkl(input_dir, output_dir)
