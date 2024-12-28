#version 330 core

in vec2 fragTexCoord;
uniform sampler2D currentTexture;
out vec4 FragColor;

void main()
{
    // Sample texture
    vec4 texColor = texture(currentTexture, fragTexCoord);

    // Calculate intensity (using red channel since it's a white gradient)
    float intensity = texColor.r;

    // Define thresholds
    float mainThreshold = 0.5;    // Adjust this for main shape size
    float borderThreshold = 0.3;  // Adjust this for border size

    // Set colors based on thresholds
    if (intensity > mainThreshold) {
        // Main shape - white
        FragColor = vec4(1.0, 1.0, 1.0, 1.0);
    }
    else if (intensity > borderThreshold) {
        // Border - dark gray
        FragColor = vec4(0.3, 0.3, 0.3, 1.0);
    }
    else {
        // Everything else - transparent
        FragColor = vec4(0.0, 0.0, 0.0, 0.0);
    }
}
