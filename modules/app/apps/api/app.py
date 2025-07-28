from flask import Flask, request, jsonify, Blueprint
from flask_cors import CORS
from groq import Groq
import os

app = Flask(__name__)
CORS(app, resources={"/api/*": {"origins": "*"}})

# Retrieve the API key from the environment
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
if GROQ_API_KEY:
    client = Groq(api_key=GROQ_API_KEY)
else:
    client = None
    print("Warning: GROQ_API_KEY environment variable not set. API calls will use default responses.")

def get_terraform_question():
    """Fetches a Terraform question from Groq API or returns a default message if the API key is missing."""
    if not client:
        return "I can't get the question - API key not configured"
    
    try:
        completion = client.chat.completions.create(
            model="llama3-8b-8192",  # Using a more stable model
            messages=[
                {"role": "system", "content": "You are a Terraform teacher responsible for Terraform class."},
                {"role": "user", "content": "Provide a Terraform configuration trivia question and only the question."},
            ],
            temperature=0.7,
            max_tokens=1024,
            top_p=1,
            stream=False,
            stop=None,
        )
        
        question = completion.choices[0].message.content
        return question
    except Exception as e:
        print(f"Error fetching question from Groq: {str(e)}")
        return f"Failed to generate question. Error: {str(e)}"

def get_answer_feedback(question, answer):
    """Submits question and answer to Groq API for feedback or returns a default message if the API key is missing."""
    if not client:
        return "I can't get feedback - API key not configured"
    
    try:
        prompt = f"Question: {question}\nYour Answer: {answer}\n"
        
        completion = client.chat.completions.create(
            model="llama3-8b-8192",  # Using a more stable model
            messages=[
                {"role": "system", "content": "You are a Terraform teacher responsible for Terraform class."},
                {"role": "user", "content": (
                    f"Provide correct/incorrect feedback for {prompt} "
                    "Provide feedback for completely incorrect answers only, otherwise, just say 'Correct'. "
                    "Correctness is extremely important. Always err on the side of correctness."
                )},
            ],
            temperature=0.3,
            max_tokens=1024,
            top_p=1,
            stream=False,
            stop=None,
        )
        
        feedback = completion.choices[0].message.content
        return feedback
    except Exception as e:
        print(f"Error getting feedback from Groq: {str(e)}")
        print(f"API Key present: {bool(GROQ_API_KEY)}")
        print(f"Client initialized: {bool(client)}")
        return f"Failed to get feedback. Error: {str(e)}"

# Create a Blueprint for API routes with the prefix /api
api_bp = Blueprint('api', __name__, url_prefix='/api')

@api_bp.route('/healthcheck', methods=['GET'])
def healthcheck():
    """Simple healthcheck endpoint to verify that the service is running."""
    return jsonify({
        "status": "ok",
        "groq_api_configured": bool(GROQ_API_KEY),
        "client_initialized": bool(client)
    })

@api_bp.route('/question', methods=['GET'])
def question_endpoint():
    """API endpoint to get a Terraform question."""
    question_text = get_terraform_question()
    return jsonify({"question": question_text})

@api_bp.route('/submit', methods=['POST'])
def submit():
    """API endpoint to submit an answer and get feedback."""
    data = request.get_json()
    question_text = data.get('question')
    user_answer = data.get('answer')
    
    if not question_text or not user_answer:
        return jsonify({"error": "Question and answer are required."}), 400
    
    feedback_text = get_answer_feedback(question_text, user_answer)
    return jsonify({"feedback": feedback_text})

# Register the Blueprint with the Flask application
app.register_blueprint(api_bp)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')  # Run on all interfaces for Docker