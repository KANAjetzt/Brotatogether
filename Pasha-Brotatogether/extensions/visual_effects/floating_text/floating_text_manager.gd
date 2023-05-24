extends FloatingTextManager

func display(value:String, text_pos:Vector2, color:Color = Color.white, icon:Resource = null, p_duration:float = duration, always_display:bool = false, p_direction:Vector2 = direction)->void :
	if get_tree().is_network_server():
		var rpc_data = {}
		rpc_data["value"] = value
		rpc_data["position"] = text_pos
		rpc_data["color"] = color
		$"/root/networking".rpc("display_floating_text", rpc_data)
	
	.display(value, text_pos, color, icon, p_duration, always_display, p_direction)