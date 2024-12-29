#version 330 core

in vec2 fragTexCoord;
uniform sampler2D currentTexture;
uniform vec2 texelSize;
uniform bool isTransparent;
out vec4 FragColor;

float getMinTransparentDistance() {
    float minDist = 100.0;
    float searchRadius = 10.0;

    // Get center pixel alpha
    vec4 centerColor = texture(currentTexture, fragTexCoord);

    // Early exit if we're in fully transparent area
    if(centerColor.a < 0.1) {
        return 0.0;
    }

    // If we're in fully opaque area, search for nearest transparent pixel
    for(float y = -searchRadius; y <= searchRadius; y += 1.0) {
        for(float x = -searchRadius; x <= searchRadius; x += 1.0) {
            vec2 offset = vec2(x, y) * texelSize;
            vec2 sampleCoord = fragTexCoord + offset;
            vec4 sampleColor = texture(currentTexture, sampleCoord);

            if(sampleColor.a < 0.1) {
                float dist = sqrt(x*x + y*y); // Use actual pixel distance
                minDist = min(minDist, dist);
            }
        }
    }

    return minDist == 100.0 ? searchRadius : minDist;
}

void main()
{
    // Gaussian kernel weights for 3x3
    float kernel[9] = float[](
        0.0625, 0.125, 0.0625,
        0.125,  0.25,  0.125,
        0.0625, 0.125, 0.0625
    );

    vec2 offsets[9] = vec2[](
        vec2(-1, -1), vec2(0, -1), vec2(1, -1),
        vec2(-1,  0), vec2(0,  0), vec2(1,  0),
        vec2(-1,  1), vec2(0,  1), vec2(1,  1)
    );

    float blurredIntensity = 0.0;
    for(int i = 0; i < 9; i++) {
        vec2 sampleCoord = fragTexCoord + offsets[i] * texelSize;
        blurredIntensity += texture(currentTexture, sampleCoord).r * kernel[i];
    }

    float mainThreshold = 0.05;
    float smoothWidth = 0.02;
    float alpha = smoothstep(mainThreshold - smoothWidth, mainThreshold + smoothWidth, blurredIntensity);

    // Adjusted color tinting
    vec3 innerColor = vec3(0.1, 0.2, 0.05);  // Darker inner color
    vec3 outerColor = vec3(0.5, 0.6, 0.2);   // Brighter outer color

    float dist = getMinTransparentDistance();
    // Wider gradient range - adjust these values to control gradient width
    float minDist = 0.0;
    float maxDist = 10.0;
    float normalizedDist = clamp((dist - minDist) / (maxDist - minDist), 0.0, 1.0);

    vec3 finalColor = mix(innerColor, outerColor, normalizedDist);
    // FragColor = vec4(finalColor, alpha);

    // Add height-based darkening
    float heightThreshold = 0.475; // Midpoint of texture
    float darkeningStrength = 0.5; // How dark it gets (0 = black, 1 = no effect)
    float heightFactor = smoothstep(heightThreshold - 0.02, heightThreshold + 0.02, fragTexCoord.y);
    finalColor *= mix(darkeningStrength, 1.0, heightFactor);

    if (isTransparent) {
        alpha = alpha * 0.5;
    }

    FragColor = vec4(finalColor, alpha);
}