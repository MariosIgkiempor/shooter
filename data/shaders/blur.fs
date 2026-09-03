#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform vec2 texel_size; // 1.0 / render texture resolution
uniform vec2 direction;  // (radius, 0) horizontal pass, (0, radius) vertical pass

void main()
{
    float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec2 step = texel_size * direction;

    vec4 result = texture(texture0, fragTexCoord) * weights[0];
    for (int i = 1; i < 5; i++) {
        vec2 offset = step * float(i);
        result += texture(texture0, fragTexCoord + offset) * weights[i];
        result += texture(texture0, fragTexCoord - offset) * weights[i];
    }

    finalColor = result * colDiffuse * fragColor;
}
