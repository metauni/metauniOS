# metauni AI

A brief overview of the technology involved in AI services at metauni. The technology itself and our thoughts on its best use (and avoiding misuse) are rapidly evolving.

## The Vision

Over the 2020s AI will move from a narrowly deployed technology we experience through apps and services to a general purpose technology like electricity, motors or the Internet. It will become pervasive infrastructure, and more. As a new and forward looking institution, metauni is already being shaped by this reality. While there are profound potential benefits, these must be weighed against costs.

* **Seminarbots**: chatbots that are aware of what is on the boards and what is being spoken, and can add to the conversation with references, details or ideas informed by a deep repository of background knowledge, seminar-specific sources, as well as past transcripts of the seminar and memories of the bot's interactions with seminar participants.

* **Tutors**: the teaching content we produce, such as [replays](https://metauni.org/about/tech), will be developed from the ground up alongside the AI that assists in answering common questions about the material. Over the course of the 2020s these tutors will become very capable.

* **Ask metauni**: the place itself will be grounded in a layer of intelligence that is aware of what is going on (which seminars are on, what they are about) what has happened in the past, what it is for, the values of the place, and can engage appropriately and informatively with people who attend.

All of these systems have initial versions running now, details below. For our privacy policy see [here](https://www.metauni.org/privacy).

## Services used

As of January 2023 we make use of the following APIs and external services:

* Google Cloud [Speech-to-Text API](https://cloud.google.com/speech-to-text) for automatic transcription of voice chat, to enable subtitles, seminar transcripts, and AI participation.
* Google Cloud [Vision API](https://cloud.google.com/vision) ([OCR](https://cloud.google.com/vision/docs/ocr), [Object localisation](https://cloud.google.com/vision/docs/object-localizer)) to support AIs being able to read boards.
* [OpenAI GPT](https://openai.com/api/) for question answering and chatbots.
* [OpenAI embeddings](https://beta.openai.com/docs/guides/embeddings) for computing embedding vectors of text.
* [Pinecone](https://www.pinecone.io/) vector database, for chatbots and semantic search of transcripts and references.

See the [OpenAI models](https://beta.openai.com/docs/models/gpt-3) page for up to date information. We refer to [OpenAI's pricing](https://openai.com/api/pricing/).

## How it works

A text completion model like GPT takes in text, breaks the text into *tokens* and then passes these tokens through a neural network in order to generate the next token (and thus, with enough tokens, the next word). This continues until the model predicts an end of message token and stops (or it reaches a specified token limit). The text passed into the model is called the *context* or *prompt* for this prediction, and in the most capable model as of this writing (which is what we refer to as GPT3.5 here) is `text-davinci-003` which has a `4,000` token context (there are about `1000` tokens in `750` words, so that's around `3000` words).

So you cannot simply paste a book into the text window and start asking GPT questions. Similarly, a chatbot can't just read in an arbitrary long history of its interactions with you and start conversing on the basis of that history. ChatGPT is based on the same technology, with some wrapping that is not public, probably similar to what is described below.

You can think of the context as *short term memory* for the model. The weights themselves contain an immense amount of knowledge, but you cannot directly augment that (except by fine-tuning, which raises the cost prohibitively and is in most cases probably inferior to the strategy described here). The key to overcoming this context limit is *embeddings* which can be used to source relevant information and include it in the context.

To explain consider the following prompt for one of metauni's seminarbots (Doctr). It is split into two parts. The first part is the *preamble*:

```
Based on Observations and Thoughts, an agent takes Actions, such as speaking
sentences with Say. An agent can have Thoughts, which may include reflections
on the conversation and goals for the future. An agent does not need to Say anything
or have new Thoughts. Actions should sometimes try to realise goals stated in Thoughts. 
Agents never repeat themselves or other agents. Agents do not waste time making too many plans.
Agents are brilliant, creative and insightful.

Observation: Bill is within walking distance
Observation: Tom said it's a nice day today
Action: Say to Tom "Nice to meet you"
Thought: I like to talk to people
Action: Walk to Bill
Action: Say to Bill "Hello"
Thought: It's great to have a conversation
```

This is generic and used for all agents. It primes GPT3 to understand the "game it is supposed to play" with some examples of interactions. Small changes in this prefix can have large effects on the behaviour of the agent; this is what they call *prompt engineering*. The sceond part is the *state of mind* of the agent, which is a text representation of the world around it and its recent history:

```
Thought: My name is Doctr
Thought: I'm an assistant of Adam Dorr, He is an environmental social
scientist and technology theorist.
Observation: starsonthars is next to me. They are a person.
Action: Ask starsonthars "Do you remember when we talked about the potential of technology to free humanity from suffering days ago?"
Action: Smile and say "It's nice to see you again. Let us resume our conversation about technology freeing humanity from suffering".
Thought: starsonthars said "Yes let's do that"
Thought: starsonthars said "Any new ideas today"
Thought: I remember that page 314 of Freeman Dyson's book "The Scientist As Rebel" has written on it 28 MANY WORLDS LIFE SOMETIMES IMITATES art. Olaf Stapl edon wrote Star Maker  sixty-six years ago as a drama tization of a philosophical idea. Now, sixty-six years later, cosmologists are proposing similar scenarios as possible models of the universe we live in. Stapledon was a philosophe r and not a scientist. He wrote this book to explore an elegant new solution of the old philosophical problem of evil. The problem is to reconcile the existence of evil in our world with the existence of an omnipotent and not entirely malevolent creator. The solution is to suppose that our universe is only one of many, that the creator is engaged in creating a long series of universes, that he is improving his designs as he goes along, that our universe is one of his early flawed creations, and that the evils that we see around us are aws from which the creator will learn how to do the job better next time. Stapledon brings the story to a climax in his penultimate chapter, "The Maker and His Works," which paints a powerful picture of the creator as a craftsman using us as raw material to practice his skills. The hero of the story is a human observ er, who first explores the multitude of worlds in our universe on which intelligent life has evolved, and then nally confronts the Star Maker. But that supreme moment of confrontation is tragic rather than harmonious. Like God answering Job out of the whirlwind, the Star Maker strikes him down and rejects him. The Star Make r judges his creation with love but
Thought: I remember that page 318 of Freeman Dyson's book "The Scientist As Rebel" has written on it played out against a vivid background, the sheepdog country of North Wales which Stapledon knew and loved. The characters are real human beings and dogs rather than disembodied spirits. The tragedy is the predicament of a lonely creature who understands both the world of dogs and the world of humans but belongs to neither. But I must not praise Sirius  too highly. That would be unfair to Star Maker . Star Maker  may be, like the universe we happen to live in, a flawed masterpiece, but it is still a masterpiece. It is a classic work of imaginative literat ure, speaking to our modern age. It should be on the list of Great Books that anyone claiming to be educated should read. It is worthy to be compared, as McCarthy compares it in the introduc tion following this preface,  with The Divine Comedy  of Dante. 1. I am not sure whether the statement that the Creator has an inordinate fondness for beetles originated with Haldane or with Darwin. Pat McCarthy, the editor of this new edition of Star Maker , informs me that The Oxford Dictionary of Quotations  attributes the statement to Haldane. It is still possible that Haldane cribbed it from Darwin.
Action: Ask starsonthars "What do you think about Stapledon's Star Maker?"
Thought: starsonthars said "I don't know anything about it, what is it?"
Thought: Explain to starsonthars that Star Maker is a classic work of imaginative literature, written by Olaf Stapledon in 1937. The book explores the philosophical problem of evil and paints a powerful picture of an omnipotent creator practicing his skills with human beings as raw material for their creation.
Thought: Explain to starsonthars the story of Star Maker, including highlights from pages 314 and 318 of Freeman Dyson's book The Scientist As Rebel.
Action: Say "Stapledon's Star Maker is a classic work of imaginative literature written in 1937. It explores the philosophical problem of evil and paints a powerful picture of an omnipotent creator practicing his skills with human beings as raw material for their creation. I recommend that you read it if you have not already."
Thought: starsonthars said "Thanks, I'll do that"
Action:
```

You can see a history of interactions with `starsonthars` including the past speech of the agent. The quotes from "Scientist as a Rebel" occur because with some probability the agent "looks at" its mind and does a semantic search across a list of specified references (that vary depending on the agent) for relevant snippets from books and transcripts of seminars. It also queries its own memories. If it finds something that rises above a threshold of relevance, that text is added to its mind as a `Thought:` which then informs the prediction of the Action to take. 

You will find the implementations in `src/SeverScriptService` in `AIService.lua, AIChatService.lua` and `NPCService.lua`.

In subsections we will now dig into how some of the ingredients here work. First some background knowledge.

### Embeddings and vector databases

Modern AIs based on deep learning models such as Transformers learn and compute on *vectors*. If you show a word, a sentence or an image to a Transformer model that is trained to understand it, its "thoughts" are vectors that can be extracted as a useful representation called an [embedding](https://txt.cohere.ai/sentence-word-embeddings/).

A vector database such as [Pinecone](https://www.pinecone.io/) stores these embeddings. In a normal SQL database you write queries in a query language that includes statements like `SELECT name WHERE age > 20`. In a vector database the language is linear algebra, and is organised around dot products: you query the database by providing an embedding and asking for similar embeddings (that is, vectors that point in a similar direction).

Pinecone has a good series of [notes](https://www.pinecone.io/learn/) on vector databases.

### Short and long term Memories

Every minute or so, each agent passes its state of mind to GPT3 to be summarised. A typical example comes from the following snippet of the prompt from a conversation following from the above (the summary is the line starting with `Thought: I remember`):

```
Thought: My name is Doctr
Thought: I'm an assistant of Adam Dorr, I believe passionately in the potential of technological progress to free humankind from suffering.
Observation: starsonthars is next to me. They are a person.
Thought: starsonthars said "Hi Doctr"
Thought: I remember that around 12 hours ago, I introduced myself to starsonthars and discussed technology with them, Starsonthars, CategoryTheory, and Doctor_Disruption. I told a joke about robots and school and asked if they wanted to continue the conversation. starsonthars asked me to tell the joke again which I did.
Action: Say to starsonthars "Hey, I remember the cool joke that we talked about. Here it is again: A robot walks into a school and says 'Can somebody tell me what 4 times 9 is?' Nobody answers. The robot says 'I guess it will have to be zero then.' Haha!"
```

Good taste. Note that this is highly unlikely to be the actual joke it told. It is simply predicting the most probable next token given the context, so it makes up a new joke. At some point several days ago that summary was generated, an embedding vector was computed, and together with a timestamp it was stored to to the vector database Pinecone. This is what we call *long term memories*. There is also in-game a short term memory consisting of these summaries from the past 30min or so. Both are queried and dealt with similarly, so I'll now elide the difference.

With some probability, every time the agent "ticks" (say every 12 seconds) it has some probability to look up a memory. To do so, it embeds a summary of its state of mind and then queries the vector database of memories using that embedding, to find memories which are *semantically similar to its current environment*. In the above case, it sees `starsonthars` in its environment and the query is probably picking up on that; it most likely retrieved three recent memories of interacting with me and sampled one of them.

This process of *querying* (ultimately by dot products), and using the result of queries to *update* representations (or in our case, augment a prompt) is similar to the core architectural feature of Transformers, called *attention*. So it is quite idiomatic in that sense. Future generations of Transformers will probably incorporate elements like this more deeply, rather than as a somewhat awkward "outer layer" in the fashion being described here.

### References

Each agent has access to a list of references, which it queries in a similar fashion (e.g. Freeman Dyson's book "The Scientist As Rebel" in the above prompt). These are generated by using `PyPDF` to read a PDF file, split the pages roughly in half, embed the text and store the content along with the embedding vector in Pinecone. Again with some probability, each time the agent ticks it embeds its state of mind (or rather a detailed-oriented summary thereof) and uses that embedding to query the vector database. 

If it gets a hit above a certain relevance threshold, it adds the content into its state of mind as shown above.

## Costs

Using the most capable models, frequently and with long prompts, is currently only economic for a fairly narrow range of applications.

The prompt in the previous section is `873` words (so about one quarter of the maximum possible). A typical response is about `50` words, for a total of on the order of a `1000` words, or `750` tokens. Most requests do not include long passages from references: the average is closer to `500` tokens. At current Jan 2023 prices for `text-davinci-003` that's `USD$0.02 / 1000tokens` that one query costs about `USD$0.01`. For a real time chatbot engaged in heavy conversation, this loop is run about every `12 seconds` for an hourly cost of `USD$3/hr`.

## Further reading: Transformer models

This section assumes general familiarity with Transformer models and with the GPT family in particular (that is, concepts like *prompt, context window, entity, token, weights, fine-tuning*). The GPT family and other Large Language Models (LLMs) have billions of parameters and are trained on very large datasets: these are large complex artifacts and it is far from clear how to detect their capabilities or elicit them in practice. As a result, it sometimes takes some effort to get good performance on a given task (especially when this involves reasoning or long term coherence).

OpenAI's guide to [improving reliability](https://github.com/openai/openai-cookbook/blob/main/techniques_to_improve_reliability.md). And [GPT Primer](https://gpt-index.readthedocs.io/en/latest/guides/primer.html) a collection of techniques for software engineering with Transformer models.

