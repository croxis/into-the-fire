shader_type spatial;
render_mode blend_mix,depth_draw_always,cull_back,diffuse_burley,specular_disabled,unshaded,shadows_disabled;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color;
uniform float specular;
uniform float metallic;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;

varying float apparent_magnitude;
varying float intensity;
varying float mag_limit;

//uniform float mag_ref = 3.0; // Reference magnitude of intensity of 1: 1 = brightness before expanding the point size
//uniform float mag_limit = 6.0; // When we can't see stars anymore
const float e = 2.7182818284590452353602;


float log10( in float n ) {
    return log2(n) / log2(10.0);
}

float circle(vec2 position, float radius, float feather)
{
	return smoothstep(radius, radius + feather, dot(position, position) * 4.0);
}


void vertex() {
	UV=UV*uv1_scale.xy+uv1_offset.xy;
    
    // Calculate distance to camera, in parsecs
	vec3 view_vertex = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance_parsecs = distance(view_vertex, vec3(0.0, 0.0, 0.0));
    
    // Calculate magnitude
    // https://github.com/tlareywi/Infinitarium/blob/master/Renderers/Vulkan/starsDefault.vert.glsl
    apparent_magnitude = INSTANCE_CUSTOM.x - 5.0 * ( 1.0 - log10(distance_parsecs));
    
    
    //https://astronomy.stackexchange.com/questions/33145/rendering-stars-in-3d-space-absmag-to-opengl-scale-values
	// So, that is for individual pixel brightness, not the "size", boo
    // Luminocity has been pre-calculated. It is in INSTANCE_CUSTOM.y
    //https://github.com/paulhoux/Cinder-Samples/blob/master/Stars/assets/shaders/stars.vert
    //https://www.researchgate.net/publication/287031803_Single-pass_Rendering_of_Day_and_Night_Sky_Phenomena
	
	//2022.7.29: Consider this as an option: https://astronomy.stackexchange.com/questions/36406/best-way-to-simulate-star-sizes-to-scale-in-celestial-sphere?rq=1
	
	// 2022.07.31 Method https://erwanleroy.com/rendering-a-plausible-night-sky-making-stars-gizmo-part-2-2/
	float base_point_size = sqrt(2);  // The minimum size needed to prevent aliasing issues
	float intensity_ref = 1.0;
	float mag_ref = INSTANCE_CUSTOM.z;
	mag_limit = INSTANCE_CUSTOM.w;
	intensity = intensity_ref * pow(e, (0.921034 * mag_ref - 0.921034 * apparent_magnitude));
	if (intensity > 1.0){
		base_point_size = log2(intensity)/log(6.0) * base_point_size;
	}
	POINT_SIZE = base_point_size;
}


void fragment() {
    // TODO: mag_limit-1 fade the alpha
    if (apparent_magnitude > mag_limit) {
        discard;
    }
	ALBEDO = COLOR.rgb;
	
    float dist = length(POINT_COORD - vec2(0.5, 0.5)); 
    if (dist > 0.5f){
		discard;
	} else if (dist > 0.3f){
        ALPHA = -10.0 * dist + 5.0;
    } else {
        //ALPHA = 0.1;
    }
	
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
    DEPTH = 0.9999;
}
