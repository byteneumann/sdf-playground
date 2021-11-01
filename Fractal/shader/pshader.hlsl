struct ps_input
{
	float4 pos : SV_POSITION;
	float2 screenpos : SCREENPOS;
};

struct ps_output
{
	float4 color : SV_TARGET;
};

cbuffer camera
{
	float3 eye;
	float3 front_vec;
	float3 right_vec;
	float3 top_vec;
	
	float3 debug_plane_point;
	float3 debug_plane_normal;

	float _unused;
	float stime;
	float free_param;
};

static const float pi = 3.14159265f;
static const float dist_eps = 0.0001f;    // how close to the object before terminating
static const float grad_eps = 0.0001f;    // how far to move when computing the gradient
static const float shadow_eps = 0.0003f;   // how far to step along the light ray when looking for occluders
static const float max_dist_check = 1e30; // maximum practical number
static const float3 lighting_dir = normalize(float3(-1.f, -1.f, 1.5f));

static const uint NUM_ITERS = 100;
static const uint NUM_REFLS = 1;

static const float debug_ruler_scale = 0.01f;

float sdf_foreground(float3 p);
float sdf_background(float3 p);
//float4 col(float3 p);

float opUnion(float d1, float d2)
{
	return min(d1, d2);
}

float opUnion(float d1, float d2, float d3)
{
	return min(d1, min(d2, d3));
}

float opUnion(float d1, float d2, float d3, float d4)
{
	return min(d1, min(d2, min(d3, d4)));
}

float opIntersect(float d1, float d2)
{
	return max(d1, d2);
}

float3 opTranslate(float3 p, float3 delta)
{
	return p - delta;
}

float sdf(float3 p, uint shader_pass)
{
	switch (shader_pass)
	{
	case 0: return sdf_foreground(p);
	case 1: return sdf_background(p);
	default: return 0.0f;
	}
}

float sdSphere(float3 p, float r)
{
	return length(p) - r;
}

float sdBox(float3 p, float3 size)
{
	const float3 q = abs(p) - size;
	return length(max(q, 0.f)) + min(max(q.x, max(q.y, q.z)), 0.f);
}

float sdPlane(float3 p, float3 normal)
{
	//return length(dot(p, normal) * normal);
	return dot(p, normal);
}

/**
 * torus around y-axis
 * @param r1 large radius
 * @param r2 small radius
 */
 //TODO check dimensions
float sdTorus(float3 p, float r1, float r2)
{
	const float2 q = float2(length(p.xz) - r1, p.y);
	return length(q) - r2;
}

//TODO check dimensions
float sdCylinder(float3 p, float r, float h)
{
	const float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
	return min(max(d.x, d.y), 0.0f) + length(max(0.0f, d));
}

//TODO check dimensions
float sdCylinderRounded(float3 p, float r1, float h, float r2)
{
	const float2 d = float2(length(p.xz) - r1 + r2, abs(p.y) - h);
	return min(max(d.x, d.y), 0.0f) + length(max(0.0f, d)) - r2;
}

/**
 * cone (bound), origin is at center of base
 * @param alpha angle between y-axis and cone in radians
 * @param h height of the cone
 */
//TODO check dimensions
float sdCone(float3 p, float alpha, float h)
{
	const float2 cs = float2(cos(alpha), sin(alpha));
	const float q = length(p.xz);
	return max(dot(cs, float2(q, p.y - h)), -p.y);
}

float sdPawn(float3 p, float size)
{
	return opUnion(
		sdCylinderRounded(opTranslate(p, float3(0, 0.05 * size, 0)), 0.5f * size, 0.1f * size, 0.05f * size), // base
		sdTorus(opTranslate(p, float3(0, 0.225f * size, 0)), 0.3f * size, 0.05f * size), // base torus
		sdCone(opTranslate(p, float3(0, 0.2f * size, 0)), 0.125f * pi, 0.8f * size), // body cone
		opUnion(
			sdTorus(opTranslate(p, float3(0, 0.8f * size, 0)), 0.125f * size, 0.05f * size), // top torus
			sdSphere(opTranslate(p, float3(0, size, 0)), 0.25f * size) // top
			)
		);
}

float raySphere(float3 p, float3 dir, float r)
{
	return length(cross(p, dir)) - r;
}

float sdPlaneFast(float3 pos, float3 dir, float3 plane_norm)
{
	float plane_dist = dot(pos, plane_norm);
	float fast_skip = dot(dir, dir);
	if (fast_skip > 0.5f)
	{
		return plane_dist / (saturate(dot(dir, -plane_norm)) + 0.000000001f);
	}
	else
	{
		return plane_dist;
	}
}

float3 debug_plane_color(float scene_distance)
{
	float int_steps;
	float frac_steps = abs(modf(scene_distance / debug_ruler_scale, int_steps)) * 1.2f;
	float band_steps = modf(int_steps / 5.f, int_steps);

	float3 band_color = band_steps > 0.7f ? float3(1.f, 0.25f, 0.25f) : float3(0.75f, 0.75f, 1.f);
	frac_steps = scene_distance < 5.f ? frac_steps : 0.5f;
	float3 col = frac_steps < 1.f ? frac_steps * frac_steps * float3(1.f, 1.f, 1.f) : band_color;
	col.g = scene_distance < 0.f ? (scene_distance > -0.01f ? 1.f : 0.f) : col.g;
	return col;
}

float2 sdf_debug(float3 p, float3 dir, out float3 material_property)
{
	float distance_cut_plane = sdPlaneFast(p - debug_plane_point, dir, debug_plane_normal);
	float distance_scene = sdf_foreground(p); // , dir, material_property);
	if (dot(debug_plane_normal, debug_plane_normal) > 0.5f && distance_cut_plane < distance_scene.x)
	{
		distance_scene = sdf_foreground(p); // , float3(0.f, 0.f, 0.f), material_property);
		material_property = debug_plane_color(distance_scene);
		return distance_cut_plane;
	}
	else
	{
		return distance_scene;
	}
}

float3 normal6(float3 p, uint shader_pass, float h = 0.0001f)
{
	// central differences
	// 6 evaluations
	return normalize(float3(
		sdf(p + float3(h, 0, 0), shader_pass) - sdf(p - float3(h, 0, 0), shader_pass),
		sdf(p + float3(0, h, 0), shader_pass) - sdf(p - float3(0, h, 0), shader_pass),
		sdf(p + float3(0, 0, h), shader_pass) - sdf(p - float3(0, 0, h), shader_pass)
		));
}

float3 normal4(float3 p, uint shader_pass, float h = 0.0001f)
{
	// forward differences
	// 4 evaluations
	const float q = sdf(p, shader_pass);
	return normalize(float3(
		sdf(p + float3(h, 0, 0), shader_pass) - q,
		sdf(p + float3(0, h, 0), shader_pass) - q,
		sdf(p + float3(0, 0, h), shader_pass) - q
		));
}

float3 normal4_tetra(float3 p, uint shader_pass, float h = 0.0001f)
{
	const float2 k = float2(1, -1);
	return normalize(
		k.xyy * sdf(p + k.xyy * h, shader_pass) +
		k.yyx * sdf(p + k.yyx * h, shader_pass) +
		k.yxy * sdf(p + k.yxy * h, shader_pass) +
		k.xxx * sdf(p + k.xxx * h, shader_pass)
	);
}

//float ray(float3 eye, float3 dir)
//{
//	return opOr(raySphere(eye, dir, float3(0, 0, 0), 1), raySphere(eye, dir, float3(3, 0, 0), 0.6f + 0.06f * cos(stime)));
//}

float sdf_foreground(float3 p)
{
	float d;
	//d = opUnion(sdSphere(p, 1), sdSphere(opTranslate(p, float3(3, 0, 0)), 0.6f + 0.06f * cos(stime)));
	//d = opUnion(d, sdPlane(opTranslate(p, float3(0, -1, 0)), float3(0, 1, 0)));
	//d = opUnion(d, sdBox(opTranslate(p, float3(-3, 0, 0)), float3(1, 2, 1)));
	//d = sdSphere(p, 1);
	d = sdPawn(p, 1.0f);
	return d;
}

float sdf_background(float3 p)
{
	float d = sdPlane(opTranslate(p, float3(0, -1, 0)), float3(0, 1, 0));
	return d;
}

void ps_main(ps_input input, out ps_output output)
{
	const float3 eye_dir = normalize(front_vec + input.screenpos.x * right_vec + input.screenpos.y * top_vec);

	uint shader_pass = 0;
	float3 pos = eye;
	float3 dir = eye_dir;
	float3 col = float3(0.0f, 0.0f, 0.0f);
	//if (ray(p, dir) > 0.0f)
	uint hit = 0;
	{
		// https://erleuchtet.org/~cupe/permanent/enhanced_sphere_tracing.pdf
		float omega = 1.6f; // in [1.0; 2.0]
		float last_d = 0.0f;
		for (uint iter = 0; iter < NUM_ITERS && hit < NUM_REFLS; ++iter)
		{
			float d = sdf(pos, shader_pass);
			if (omega > 1.0f && last_d * omega > last_d + d) // no overlap
			{
				// undo last step
				// fall back to normal ray marching
				// solution must be in [pos; pos + dir * d]
				pos -= dir * last_d * omega;
				omega = 1.0f;
				continue;
			}
			if (d < dist_eps)
			{
				const float3 normal = normal6(pos, shader_pass);
				const float shading = clamp(dot(-normal, lighting_dir), 0.0f, 1.0f);
				//const float shading = 0.5f * (1.0f + iter / 100.0f);
				//const float shading = clamp(0.1f * distance_travelled, 0.5f, 1.0f);
				col += float3(1.0f, 1.0f, 0.0f) * shading;

				++hit;
				if (hit < NUM_REFLS) // reflection
				{
					dir = reflect(dir, normal); // Snell's law
					omega = 1.6f;
					d = last_d; // one step backwards
					last_d = 0.0f;
					iter = 0;
				}
				else // hit (no more reflections)
				{
					break;
				}
			}
			pos += dir * d * omega;
			last_d = d;
		}
	}
	shader_pass = 1;
	if (hit < NUM_REFLS)
	{
		for (uint iter = 0; iter < NUM_ITERS; ++iter)
		{
			const float d = sdf(pos, shader_pass);
			if (d < dist_eps)
			{
				const float3 normal = normal6(pos, shader_pass);
				const float shading = clamp(dot(-normal, lighting_dir), 0.0f, 1.0f);
				col += float3(0.7f, 0.4f, 0.4f) * shading;
				break;
			}
			pos += dir * d;
		}
	}

	output.color = float4(col / min(1.0f, 1.0f + hit), 1.0f);
};