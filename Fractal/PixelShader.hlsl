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
};

static const float dist_eps = 0.001f;
static const float grad_eps = 0.001f;
static const float3 lighting_dir = normalize(float3(-3.f, -1.f, 2.f));

float sdSphere(float3 p, float r)
{
	return length(p) - r;
}

float sdBox(float3 p, float3 size)
{
	float3 q = abs(p) - size;
	return length(max(q, 0.f)) + min(max(q.x, max(q.y, q.z)), 0.f);
}

float fractal1(float3 p, uint depth)
{
	float d = 1e20;
	float3 abspos = abs(p);
	float scale = 1.f;
	for (uint iter = 0; iter < depth; ++iter)
	{
		float new_d = sdBox(abspos, float3(1.f, 1.f, 1.f)) / scale;
		d = min(d, new_d);

		if (abspos.z > abspos.y)
		{
			abspos.yz = abspos.zy;
		}
		if (abspos.y > abspos.x)
		{
			abspos.xy = abspos.yx;
		}

		abspos.x -= 4.f / 3.f;
		abspos *= 3.f;
		scale *= 3.f;
	}
	return d;
}

float fractal2(float3 p, uint depth)
{
	float d = 1e20;
	float3 abspos = abs(p);
	float scale = 1.f;
	for (uint iter = 0; iter < depth; ++iter)
	{
		float new_d = sdBox(abspos, float3(1.f, 1.f, 1.f)) / scale;
		d = min(d, new_d);

		if (abspos.z > abspos.y)
		{
			abspos.yz = abspos.zy;
		}
		if (abspos.y > abspos.x)
		{
			abspos.xy = abspos.yx;
		}

		if (abspos.y > 1.f / 3.f)
		{
			abspos.y -= 2.f / 3.f;
		}
		if (abspos.z > 1.f / 3.f)
		{
			abspos.z -= 2.f / 3.f;
		}

		abspos.x -= 10.f / 9.f;
		abspos *= 9.f;
		scale *= 9.f;
	}
	return d;
}

float sphere(float3 p, float3 pos, float radius)
{
	return length(pos - p) - radius;
}

float ellipsoid_exact(float3 p, float3 pos, float3 radii)
{
	float3 dist = pow(pos - p, 2.0f);
	float3 radii_sq = pow(radii, -2.0f);
	float lhs = dot(dist, radii_sq);
	return sqrt(lhs) - 1.0f;
}

// https://iquilezles.org/www/articles/ellipsoids/ellipsoids.htm
float ellipsoid_approx(float3 p, float3 pos, float3 radii)
{
	const float3 q = p - pos;
	float k1 = length(q / radii);
	float k2 = length(q / (radii * radii));
	return k1 * (k1 - 1.0f) / k2;
}

// https://iquilezles.org/www/articles/ellipsedist/ellipsedist.htm
float ellipsoid_symmetric(float3 p, float3 pos, float2 radii)
{
	const float3 pp = p - pos;
	const float2 q = abs(float2(pp.x, length(pp.yz))); //BUG
	const bool s = dot(q / radii, q / radii);
	float w = s > 1.0f ? atan2(q.y * radii.x, q.x * radii.y) : ((radii.x * (q.x - radii.x) < radii.y * (q.y - radii.y)) ? 1.5707963 : 0.0);
	for (int i = 0; i < 4; ++i)
	{
		const float2 cs = float2(cos(w), sin(w));
		const float2 u = radii * float2(cs.x, cs.y);
		const float2 v = radii * float2(-cs.y, cs.x);
		w += dot(q - u, v) / (dot(q - u, u) + dot(v, v));
	}
	return length(q - radii * float2(cos(w), sin(w))) * sign(s);
}

float map(float3 p)
{
	return min(sphere(p, float3(2, 0, 0), 1),
		min(ellipsoid_exact(p, float3(-2, 0, 0), float3(1, 2, 3)),
			min(ellipsoid_approx(p, float3(-6, 0, 0), float3(1, 2, 3)),
				ellipsoid_symmetric(p, float3(6, 0, 0), float2(1, 2))
			)
		)
	);
}

float3 grad(float3 p, float baseline)
{
	float d1 = map(p - float3(grad_eps, 0.f, 0.f)) - baseline;
	float d2 = map(p - float3(0.f, grad_eps, 0.f)) - baseline;
	float d3 = map(p - float3(0.f, 0.f, grad_eps)) - baseline;
	return normalize(float3(d1, d2, d3));
}

void ps_main(ps_input input, out ps_output output)
{
	float3 dir = normalize(front_vec + input.screenpos.x * right_vec + input.screenpos.y * top_vec);

	float3 pos = eye;
	float3 col = float3(0.1f, 0.1f, 0.f);
	for (uint iter = 0; iter < 100; ++iter)
	{
		float d = map(pos);
		if (d < dist_eps)
		{
			float3 normal = grad(pos, d);
			float shading = clamp(dot(normal, lighting_dir), 0.f, 1.f);

			col = float3(1.f, 1.f, 0.f) * shading;
			break;
		}
		pos += dir * d;
	}

	output.color = float4(col, 1.f);
};