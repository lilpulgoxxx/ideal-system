FROM wordpress:php8.2-apache-alpine

# Instalar las extensiones PHP requeridas, herramientas y wp-cli
RUN apk update && apk add --no-cache \
    curl \
    zip \
    unzip \
    git \
    mysql-client \
    libzip-dev \
    gmp-dev \
    freetype-dev \
    jpeg-dev \
    libpng-dev \
    icu-dev \
    composer \
    wp-cli \
    $PHPIZE_DEPS

RUN docker-php-ext-configure zip && \
    docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        zip \
        gmp \
        intl \
        gd

# Instalar Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Definir directorio de trabajo
WORKDIR /var/www/html

# Incrustar el contenido de wp-cli.config.php directamente (crea wp-config.php)
RUN cat > wp-config.php <<'EOL'
<?php
/**
 * Utilizado por wp-cli durante la construcción de Docker en Railway.app - INCRUSTADO EN EL DOCKERFILE
 */
return array(
    'dbuser' => getenv('RAILWAY_MYSQL_USER'),
    'dbpass' => getenv('RAILWAY_MYSQL_PASSWORD'),
    'dbname' => getenv('RAILWAY_MYSQL_DATABASE'),
    'dbhost' => getenv('RAILWAY_MYSQL_HOST') . ':' . getenv('RAILWAY_MYSQL_PORT'),
    'table_prefix' => 'wp_',
    'wp_debug' => false,
);
EOL

# Configurar WordPress y copiar el plugin (se omite la activación del plugin)
RUN wp core install --path='/var/www/html' --url="https://${RAILWAY_STATIC_URL}" --title="Llama3 Chatbot Site" --admin_user="admin" --admin_password="password" --admin_email="admin@example.com" --skip-email --allow-root && \
    wp option update siteurl "https://${RAILWAY_STATIC_URL}" --allow-root && \
    wp option update home "https://${RAILWAY_STATIC_URL}" --allow-root && \
    mkdir -p /var/www/html/wp-content/plugins/llama3-chatbot-pro && \
    cat > /var/www/html/wp-content/plugins/llama3-chatbot-pro/llama3-chatbot.php <<'PHP_PLUGIN_CODE'
<?php
/**
 * Plugin Name: Llama 3 Chatbot Professional
 * Plugin URI:  https://example.com/
 * Description: Chatbot profesional potenciado por Llama 3, plugin de WordPress con funcionalidades avanzadas.
 * Version:     1.3.0
 * Author:      Your Name
 * Author URI:  https://example.com/
 * License:     GPL2
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: llama3-chatbot
 * Domain Path: /languages
 */

defined('ABSPATH') or die('¡No se permiten accesos directos!');

if (session_status() == PHP_SESSION_NONE) {
    session_start();
}

use Transformers\Transformer;
use Transformers\Pipelines\TextGenerationPipeline;

$plugin_dir = plugin_dir_path(__FILE__);
$autoload_path = $plugin_dir . 'vendor/autoload.php';

if (!file_exists($autoload_path)) {
    add_action('admin_notices', function() use ($plugin_dir) {
        ?>
        <div class="error notice is-dismissible">
            <p><?php _e( 'Llama 3 Chatbot: <strong>Dependencias no instaladas.</strong>', 'llama3-chatbot' ); ?></p>
            <p><?php _e( 'Instala las dependencias usando Composer:', 'llama3-chatbot' ); ?></p>
            <ol>
                <li><?php _e( 'Accede al servidor vía SSH/terminal.', 'llama3-chatbot' ); ?></li>
                <li><?php printf( __( 'Navega al directorio del plugin: <code>%s</code>', 'llama3-chatbot' ), esc_html( $plugin_dir ) ); ?></li>
                <li><?php _e( 'Ejecuta: <code>composer install</code>', 'llama3-chatbot' ); ?></li>
                <li><?php _e( 'Recarga la página después de finalizar Composer.', 'llama3-chatbot' ); ?></li>
            </ol>
            <button type="button" class="notice-dismiss"><span class="screen-reader-text"><?php _e( 'Descartar aviso.', 'llama3-chatbot' ); ?></span></button>
        </div>
        <?php
    });
    return;
}

require_once $autoload_path;

try {
    // Se utiliza el modelo lilmeaty/Jaja-small-v4 en lugar de meta-llama/Llama-3-8B
    $transformer = Transformer::fromPretrained('lilmeaty/Jaja-small-v4');
    $textGenerationPipeline = new TextGenerationPipeline($transformer);
    error_log("Llama 3 Chatbot: Modelo/pipeline cargado en " . gethostname());
} catch (Exception $e) {
    add_action('admin_notices', function() use ($e) {
        ?>
        <div class="error notice is-dismissible">
            <p><?php _e( 'Llama 3 Chatbot: Error al cargar el modelo. Revisa la configuración/logs.', 'llama3-chatbot' ); ?></p>
            <button type="button" class="notice-dismiss"><span class="screen-reader-text"><?php _e( 'Descartar aviso.', 'llama3-chatbot' ); ?></span></button>
        </div>
        <?php
    });
    error_log('Llama 3 Chatbot: Error al cargar el modelo: ' . $e->getMessage());
    return;
}

if (!isset($_SESSION['llama3_chatbot_history'])) {
    $_SESSION['llama3_chatbot_history'] = [];
}

function generarImagenDesdeAPI_llama3_chatbot(string $prompt): ?string {
    $apiEndpoint = 'https://api-inference.huggingface.co/models/stabilityai/stable-diffusion-xl-base-1.0';
    $apiKey = esc_attr(get_option('llama3_chatbot_hf_api_key'));

    if (empty($apiKey)) {
        error_log('Llama 3 Chatbot: Falta la clave API de HF para imágenes.');
        return null;
    }

    $headers = [
        'Authorization: Bearer ' . $apiKey,
        'Content-Type: application/json'
    ];
    $postData = json_encode(['inputs' => $prompt]);

    $ch = curl_init($apiEndpoint);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

    if (curl_errno($ch)) {
        error_log('Llama 3 Chatbot: Error cURL para imagen: ' . curl_error($ch));
        curl_close($ch);
        return null;
    }
    curl_close($ch);

    if ($httpCode === 200) {
        $imageData = base64_encode($response);
        return 'data:image/png;base64,' . $imageData;
    } else {
        error_log("Llama 3 Chatbot: Error API imagen. Código: " . $httpCode . ", Respuesta: " . $response);
        return null;
    }
}

function generarMusicaDesdeAPI_llama3_chatbot(string $prompt): ?string {
    $apiEndpoint = 'https://api-inference.huggingface.co/models/eleutherai/musicgen-small';
    $apiKey = esc_attr(get_option('llama3_chatbot_hf_api_key'));

    if (empty($apiKey)) {
        error_log('Llama 3 Chatbot: Falta la clave API de HF para música.');
        return null;
    }

    $headers = [
        'Authorization: Bearer ' . $apiKey,
        'Content-Type: application/json'
    ];
    $postData = json_encode(['inputs' => $prompt]);

    $ch = curl_init($apiEndpoint);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

    if (curl_errno($ch)) {
        error_log('Llama 3 Chatbot: Error cURL para música: ' . curl_error($ch));
        curl_close($ch);
        return null;
    }
    curl_close($ch);

    if ($httpCode === 200) {
        $musicData = base64_encode($response);
        return 'data:audio/wav;base64,' . $musicData;
    } else {
        error_log("Llama 3 Chatbot: Error API música. Código: " . $httpCode . ", Respuesta: " . $response);
        return null;
    }
}

function inferirTextoPipelineOptimo_llama3_chatbot(string $prompt, TextGenerationPipeline $pipeline, array $generationConfig = [], array &$conversationHistory): array|false {
    $fullPrompt = "";
    foreach ($conversationHistory as $message) {
        $fullPrompt .= $message['role'] . ": " . $message['content'] . "\n";
    }
    $fullPrompt .= "user: " . $prompt;
    $config = array_merge([
        'max_new_tokens' => intval(get_option('llama3_chatbot_max_tokens', 150)),
        'temperature' => floatval(get_option('llama3_chatbot_temperature', 0.8)),
        'top_p' => floatval(get_option('llama3_chatbot_top_p', 0.9)),
    ], $generationConfig);
    try {
        $response = $pipeline->generateText($fullPrompt, $config);
        $conversationHistory[] = ['role' => 'user', 'content' => $prompt];
        $_SESSION['llama3_chatbot_history'] = $conversationHistory;
        return $response;
    } catch (Exception $e) {
        error_log('Llama 3 Chatbot: Error en la generación de texto: ' . $e->getMessage());
        return false;
    }
}

add_action('admin_post_llama3_chatbot_api', 'llama3_chatbot_api_handler');
add_action('admin_post_nopriv_llama3_chatbot_api', 'llama3_chatbot_api_handler');

function llama3_chatbot_api_handler() {
    global $textGenerationPipeline, $_SESSION;

    check_ajax_referer('llama3_chatbot_nonce', 'nonce');

    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        wp_send_json_error(['error' => 'Method Not Allowed'], 405);
    }

    $input = json_decode(stripslashes(file_get_contents('php://input')), true);
    $prompt = isset($input['prompt']) && is_string($input['prompt']) ? trim(sanitize_text_field($input['prompt'])) : '';
    $configSolicitud = isset($input['generation_config']) && is_array($input['generation_config']) ? $input['generation_config'] : [];

    if (empty($prompt)) {
        wp_send_json_error(['error' => 'Invalid prompt'], 400);
    }

    header('Content-Type: text/event-stream');
    header('Cache-Control: no-cache');
    header('Connection: keep-alive');
    nocache_headers();

    $response_data = [];

    if (stripos($prompt, 'imagen') !== false || stripos($prompt, 'foto') !== false || stripos($prompt, 'dibujo') !== false) {
        $image_data_uri = generarImagenDesdeAPI_llama3_chatbot($prompt);
        if ($image_data_uri) {
            $_SESSION['llama3_chatbot_history'][] = ['role' => 'bot', 'content_type' => 'image', 'content' => 'Imagen generada', 'image_data_uri' => $image_data_uri];
            $response_data = [
                'response_type' => 'image',
                'image_data_uri' => $image_data_uri
            ];
            echo "data: " . json_encode($response_data) . "\n\n";
            flush();
            ob_flush();
        } else {
            $respuestaTexto = inferirTextoPipelineOptimo_llama3_chatbot("Error generating image. Please try again.", $textGenerationPipeline, $configSolicitud, $_SESSION['llama3_chatbot_history']);
            $response_error_data = ['response' => $respuestaTexto ?? 'Error generating image error text.'];
            echo "data: " . json_encode($response_error_data) . "\n\n";
            flush();
            ob_flush();
        }
    } else if (stripos($prompt, 'cancion') !== false || stripos($prompt, 'música') !== false || stripos($prompt, 'melodia') !== false) {
        $music_data_uri = generarMusicaDesdeAPI_llama3_chatbot($prompt);
        if ($music_data_uri) {
            $_SESSION['llama3_chatbot_history'][] = ['role' => 'bot', 'content_type' => 'music', 'content' => 'Música generada', 'music_data_uri' => $music_data_uri];
            $response_data = [
                'response_type' => 'music',
                'music_data_uri' => $music_data_uri
            ];
            echo "data: " . json_encode($response_data) . "\n\n";
            flush();
            ob_flush();
        } else {
            $respuestaTexto = inferirTextoPipelineOptimo_llama3_chatbot("Error generating music. Please try again.", $textGenerationPipeline, $configSolicitud, $_SESSION['llama3_chatbot_history']);
            $response_error_data = ['response' => $respuestaTexto ?? 'Error generating music error text.'];
            echo "data: " . json_encode($response_error_data) . "\n\n";
            flush();
            ob_flush();
        }
    } else {
        $respuestaTextArray = inferirTextoPipelineOptimo_llama3_chatbot($prompt, $textGenerationPipeline, $configSolicitud, $_SESSION['llama3_chatbot_history']);
        if ($respuestaTextArray !== false) {
            $split_responses = $respuestaTextArray;
            $token_limit = intval(get_option('llama3_chatbot_split_tokens', 5));
            $words = explode(' ', implode(' ', $split_responses));
            $chunk = '';
            $word_count = 0;

            foreach ($words as $word) {
                $chunk .= $word . ' ';
                $word_count++;
                if ($word_count >= $token_limit) {
                    $chunk = trim($chunk);
                    $chunk_response = ['response_chunk' => $chunk];
                    echo "data: " . json_encode($chunk_response) . "\n\n";
                    flush();
                    ob_flush();
                    $chunk = '';
                    $word_count = 0;
                    usleep(50);
                }
            }
            if (!empty(trim($chunk))) {
                $chunk = trim($chunk);
                $chunk_response = ['response_chunk' => $chunk];
                echo "data: " . json_encode($chunk_response) . "\n\n";
                flush();
                ob_flush();
            }
        } else {
            $response_error_data = ['error' => 'Error generating text response'];
            echo "data: " . json_encode($response_error_data) . "\n\n";
            flush();
            ob_flush();
        }
    }
    wp_die();
}

add_action('init', 'llama3_chatbot_download_handler');

function llama3_chatbot_download_handler() {
    if (isset($_GET['llama3_chatbot_download_image']) && isset($_GET['data_uri'])) {
        descargarArchivo_llama3_chatbot(sanitize_text_field($_GET['data_uri']), 'image', 'imagen_chatbot');
    } else if (isset($_GET['llama3_chatbot_download_music']) && isset($_GET['data_uri'])) {
        descargarArchivo_llama3_chatbot(sanitize_text_field($_GET['data_uri']), 'music', 'musica_chatbot');
    } else if (isset($_GET['llama3_chatbot_clear_chat']) && $_GET['llama3_chatbot_clear_chat'] === '1') {
        $_SESSION['llama3_chatbot_history'] = [];
        wp_redirect(esc_url_raw(remove_query_arg('llama3_chatbot_clear_chat')));
        exit;
    }
}

add_action('wp_enqueue_scripts', 'llama3_chatbot_enqueue_assets');

function llama3_chatbot_enqueue_assets() {
    wp_enqueue_style('llama3-chatbot-style', plugin_dir_url(__FILE__) . 'chatbot-style.css', [], '1.0');
    wp_enqueue_script('llama3-chatbot-script', plugin_dir_url(__FILE__) . 'chatbot-script.js', ['jquery'], '1.0', true);
    wp_localize_script('llama3-chatbot-script', 'llama3ChatbotData', [
        'ajaxurl' => admin_url('admin-post.php'),
        'nonce'   => wp_create_nonce('llama3_chatbot_nonce'),
    ]);
}

function llama3_chatbot_shortcode() {
    ob_start();
    $initial_message = esc_html(get_option('llama3_chatbot_initial_message', __('Welcome to the Chatbot! Ask me anything.', 'llama3-chatbot')));
    if (empty($_SESSION['llama3_chatbot_history'])) {
        $_SESSION['llama3_chatbot_history'][] = ['role' => 'bot', 'content' => $initial_message];
    }
    ?>
    <div class="chatbot-container">
        <div class="chat-header">
            <h1>Chatbot Llama 3</h1>
            <button onclick="clearChat_llama3_chatbot()"><?php _e('Clear Chat', 'llama3-chatbot'); ?></button>
        </div>
        <div class="chat-messages" id="chat-messages">
            <?php foreach ($_SESSION['llama3_chatbot_history'] as $message): ?>
                <div class="message <?php echo esc_attr($message['role']) === 'user' ? 'user-message' : 'bot-message'; ?>">
                    <?php
                        if (isset($message['content_type'])) {
                            echo esc_html($message['content']);
                            if ($message['content_type'] === 'image' && isset($message['image_data_uri'])) {
                                echo '<div class="bot-media-container">';
                                echo '<img src="' . esc_url($message['image_data_uri']) . '" alt="' . __('Generated Image', 'llama3-chatbot') . '" class="bot-media" loading="lazy">';
                                echo '</div>';
                            } else if ($message['content_type'] === 'music' && isset($message['music_data_uri'])) {
                                echo '<div class="bot-media-container">';
                                echo '<audio controls class="bot-media">';
                                echo '<source src="' . esc_url($message['music_data_uri']) . '" type="audio/wav">';
                                echo __('Your browser does not support audio playback.', 'llama3-chatbot');
                                echo '</audio>';
                                echo '</div>';
                            }
                        } else {
                             echo esc_html($message['content']);
                        }
                     ?>
                </div>
            <?php endforeach; ?>
            <div id="loading-area" class="loading-indicator" style="display:none;"><?php _e('Typing...', 'llama3-chatbot'); ?></div>
        </div>
        <div class="chat-input-area">
            <input type="text" id="prompt-input" class="chat-input" placeholder="<?php esc_attr_e('Type your message...', 'llama3-chatbot'); ?>">
            <button class="send-button" onclick="enviarMensaje_llama3_chatbot()"><?php _e('Send', 'llama3-chatbot'); ?></button>
        </div>
        <div id="api-error" class="error-message" style="display:none;"><?php _e('Error connecting to server.', 'llama3-chatbot'); ?></div>
    </div>
    <?php
    return ob_get_clean();
}
add_shortcode('llama3_chatbot', 'llama3_chatbot_shortcode');

add_action('admin_menu', 'llama3_chatbot_menu');

function llama3_chatbot_menu() {
    add_options_page(
        __('Llama 3 Chatbot Settings', 'llama3-chatbot'),
        __('Llama 3 Chatbot', 'llama3-chatbot'),
        'manage_options',
        'llama3-chatbot-settings',
        'llama3_chatbot_settings_page'
    );
}

function llama3_chatbot_settings_page() {
    if (!current_user_can('manage_options')) {
        return;
    }
    ?>
    <div class="wrap">
        <h1><?php echo esc_html(get_admin_page_title()); ?></h1>
        <form method="post" action="options.php">
            <?php
            settings_fields('llama3_chatbot_settings');
            do_settings_sections('llama3-chatbot-settings');
            submit_button(__('Save Settings', 'llama3-chatbot'));
            ?>
        </form>
    </div>
    <?php
}

add_action('admin_init', 'llama3_chatbot_register_settings');

function llama3_chatbot_register_settings() {
    register_setting(
        'llama3_chatbot_settings',
        'llama3_chatbot_hf_api_key',
        ['type' => 'string', 'sanitize_callback' => 'sanitize_text_field', 'default' => '']
    );
    register_setting(
        'llama3_chatbot_settings',
        'llama3_chatbot_initial_message',
        ['type' => 'string', 'sanitize_callback' => 'sanitize_textarea_field', 'default' => __('Welcome to the Chatbot! Ask me anything.', 'llama3-chatbot')]
    );
    register_setting(
        'llama3_chatbot_settings',
        'llama3_chatbot_max_tokens',
        ['type' => 'integer', 'sanitize_callback' => 'absint', 'default' => 150]
    );
    register_setting(
        'llama3_chatbot_settings',
        'llama3_chatbot_temperature',
        ['type' => 'number', 'sanitize_callback' => 'rest_sanitize_float', 'default' => 0.8]
    );
    register_setting(
        'llama3_chatbot_settings',
        'llama3_chatbot_top_p',
        ['type' => 'number', 'sanitize_callback' => 'rest_sanitize_float', 'default' => 0.9]
    );
    register_setting(
        'llama3_chatbot_settings',
        'llama3_chatbot_split_tokens',
        ['type' => 'integer', 'sanitize_callback' => 'absint', 'default' => 5]
    );

    add_settings_section(
        'api_settings_section',
        __('API Settings', 'llama3-chatbot'),
        'api_settings_section_callback',
        'llama3-chatbot-settings'
    );
    add_settings_section(
        'chatbot_settings_section',
        __('Chatbot Display Settings', 'llama3-chatbot'),
        'chatbot_settings_section_callback',
        'llama3-chatbot-settings'
    );
    add_settings_section(
        'generation_settings_section',
        __('Generation Settings', 'llama3-chatbot'),
        'generation_settings_section_callback',
        'llama3-chatbot-settings'
    );

    add_settings_field(
        'llama3_chatbot_hf_api_key',
        __('Hugging Face API Key', 'llama3-chatbot'),
        'hf_api_key_field_callback',
        'llama3-chatbot-settings',
        'api_settings_section'
    );
    add_settings_field(
        'llama3_chatbot_initial_message',
        __('Initial Bot Message', 'llama3-chatbot'),
        'initial_message_field_callback',
        'llama3-chatbot-settings',
        'chatbot_settings_section'
    );
    add_settings_field(
        'llama3_chatbot_max_tokens',
        __('Max Tokens (Text Generation)', 'llama3-chatbot'),
        'max_tokens_field_callback',
        'llama3-chatbot-settings',
        'generation_settings_section'
    );
    add_settings_field(
        'llama3_chatbot_temperature',
        __('Temperature (Text Generation)', 'llama3-chatbot'),
        'temperature_field_callback',
        'llama3-chatbot-settings',
        'generation_settings_section'
    );
    add_settings_field(
        'llama3_chatbot_top_p',
        __('Top P (Text Generation)', 'llama3-chatbot'),
        'top_p_field_callback',
        'llama3-chatbot-settings',
        'generation_settings_section'
    );
    add_settings_field(
        'llama3_chatbot_split_tokens',
        __('Stream Response Chunk Size (Words)', 'llama3-chatbot'),
        'split_tokens_field_callback',
        'llama3-chatbot-settings',
        'generation_settings_section'
    );
}
