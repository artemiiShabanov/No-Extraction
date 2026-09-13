shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// A roughly circular tear with jagged edges that collapses to a point; inside, an abstract
// cosmos (nebula + stars), no world preview.
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform vec3 col_deep : source_color = vec3(0.08, 0.02, 0.25);
uniform vec3 col_glow : source_color = vec3(0.15, 0.55, 0.95);
uniform vec3 col_rim : source_color = vec3(0.75, 0.45, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float t = TIME;
	// radius of the tear in this direction: a breathing disc with a jagged, drifting edge
	float ang = atan(uv.y, uv.x);
	float breathe = 0.03 * sin(t * 1.7) + 0.02 * sin(t * 3.1 + ang * 3.0);
	// sample the edge noise on a circle so it is seamless around the disc
	vec2 ring = vec2(cos(ang), sin(ang)) * 1.4 + vec2(t * 0.12, t * 0.3);
	float edge = (fbm(ring) - 0.5) * 0.3;
	float radius = max(0.012, 0.62 * open + (edge + breathe) * open);
	float d = length(uv * vec2(1.0, 0.92)) - radius;
	float inside = 1.0 - smoothstep(-0.01, 0.02, d);
	float rim = 1.0 - smoothstep(0.0, 0.05 + 0.06 * open, abs(d));
	// cosmos
	vec2 p = uv * vec2(1.6, 1.0) + vec2(t * 0.04, -t * 0.07);
	float swirl = fbm(p * 1.8 + 0.8 * fbm(p * 3.2 + t * 0.12));
	vec3 space = mix(col_deep, col_glow, smoothstep(0.35, 0.8, swirl));
	space += col_rim * pow(swirl, 6.0) * 1.5;
	vec2 sp = floor((uv + vec2(t * 0.01, 0.0)) * 140.0);
	vec2 sf = fract((uv + vec2(t * 0.01, 0.0)) * 140.0) - 0.5;
	float star = step(0.985, hash(sp)) * smoothstep(0.35, 0.0, length(sf)) * (0.6 + 0.4 * sin(t * 4.0 + hash(sp + 1.0) * 20.0));
	space += vec3(star);
	vec3 col = space * inside + col_rim * rim * (0.8 + 1.4 * open);
	ALBEDO = col;
	EMISSION = col * (1.2 + open);
	ALPHA = clamp(max(inside, rim * (0.5 + 0.5 * open)), 0.0, 1.0);
}
