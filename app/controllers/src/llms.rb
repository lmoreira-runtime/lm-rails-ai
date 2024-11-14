require 'openai'
require 'ollama-ai'

## OpenAI
def get_openai_response(prompt, system_message, model)
    client = OpenAI::Client.new
    response = client.chat(
        parameters: {
        model: model,
        messages: [
            { role: "system", content: system_message},
            { role: "user", content: prompt }
        ]
        }
    )
    response['choices'][0]['message']['content'].strip
    rescue => e
    "Error: #{e.message}"
end

## Ollama
def get_ollama_response(prompt, system_message, model) #llama3.2
    client = Ollama.new(
        credentials: { address: 'http://localhost:11434' },
        options: { server_sent_events: true }
    )

    prompt2llm = system_message + "\n\n" + prompt

    #puts "# prompt2llm: #{prompt2llm}"

    result = client.generate(
        { model: model,
        prompt: prompt2llm,
        stream: false }
    )
    response = result[0]['response'].strip.delete_prefix('"').delete_suffix('"')
    #puts "# response: #{response}"
    response
    rescue => e
        "Error: #{e.message}"
end