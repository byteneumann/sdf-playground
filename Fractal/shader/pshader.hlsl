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

static const float dist_eps = 0.0001f;    // how close to the object before terminating
static const float grad_eps = 0.0001f;    // how far to move when computing the gradient
static const float shadow_eps = 0.0003f;   // how far to step along the light ray when looking for occluders
static const float max_dist_check = 1e30; // maximum practical number
static const float3 lighting_dir = normalize(float3(-1.f, -1.f, 1.5f));

static const float debug_ruler_scale = 0.01f;

float sdSphere(float3 p, float r)
{
	return length(p) - r;
}

float sdBox(float3 p, float3 size)
{
	float3 q = abs(p) - size;
	return length(max(q, 0.f)) + min(max(q.x, max(q.y, q.z)), 0.f);
}

float map(float3 p)
{
	return sdSphere(p, 1);
}

float3 normal6(float3 p, float h = 0.0001f)
{
	// central differences
	// 6 evaluations
	return normalize(float3(
		map(p + float3(h, 0, 0)) - map(p - float3(h, 0, 0)),
		map(p + float3(0, h, 0)) - map(p - float3(0, h, 0)),
		map(p + float3(0, 0, h)) - map(p - float3(0, 0, h))
		));
}

float3 normal4(float3 p, float h = 0.0001f)
{
	// forward differences
	// 4 evaluations
	const float q = map(p);
	return normalize(float3(
		map(p + float3(h, 0, 0)) - q,
		map(p + float3(0, h, 0)) - q,
		map(p + float3(0, 0, h)) - q
		));
}

float3 normal4_tetra(float3 p, float h = 0.0001f)
{
	const float2 k = float2(1, -1);
	return normalize(
		k.xyy * map(p + k.xyy * h) +
		k.yyx * map(p + k.yyx * h) +
		k.yxy * map(p + k.yxy * h) +
		k.xxx * map(p + k.xxx * h)
	);
}

void ps_main(ps_input input, out ps_output output)
{
	const float3 dir = normalize(front_vec + input.screenpos.x * right_vec + input.screenpos.y * top_vec);

	float3 pos = eye;
	float3 col = float3(0.0f, 0.0f, 0.0f);
	for (uint iter = 0; iter < 100; ++iter)
	{
		float d = map(pos);
		if (d < dist_eps)
		{
			const float3 normal = normal6(pos);
			const float shading = clamp(dot(-normal, lighting_dir), 0.0f, 1.0f);
			col = float3(1.0f, 1.0f, 0.0f) * shading;
			break;
		}
		pos += dir * d;
	}

	output.color = float4(col, 1.0f);
};