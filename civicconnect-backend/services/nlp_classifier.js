/**
 * CivicConnect Natural Language Processing & Text Classification Engine
 *
 * Algorithm 1: Rule-Based Complaint Classification
 *   - Keyword matching with weights, category scoring, and confidence estimation.
 *
 * Algorithm 2: TF-IDF Text Feature Extraction
 *   - Tokenization, stop-word removal, term frequency (TF) and inverse document frequency (IDF).
 *
 * Algorithm 4: Cosine Similarity
 *   - Vector angle comparison between complaint descriptions for duplicate detection.
 */

const STOP_WORDS = new Set([
  'a', 'about', 'above', 'after', 'again', 'against', 'all', 'am', 'an', 'and', 'any', 'are', 'aren\'t', 'as', 'at',
  'be', 'because', 'been', 'before', 'being', 'below', 'between', 'both', 'but', 'by',
  'can', 'can\'t', 'cannot', 'could', 'couldn\'t',
  'did', 'didn\'t', 'do', 'does', 'doesn\'t', 'doing', 'don\'t', 'down', 'during',
  'each',
  'few', 'for', 'from', 'further',
  'had', 'hadn\'t', 'has', 'hasn\'t', 'have', 'haven\'t', 'having', 'he', 'he\'d', 'he\'ll', 'he\'s', 'her', 'here',
  'here\'s', 'hers', 'herself', 'him', 'himself', 'his', 'how', 'how\'s',
  'i', 'i\'d', 'i\'ll', 'i\'m', 'i\'ve', 'if', 'in', 'into', 'is', 'isn\'t', 'it', 'it\'s', 'its', 'itself',
  'let\'s',
  'me', 'more', 'most', 'mustn\'t', 'my', 'myself',
  'no', 'nor', 'not',
  'of', 'off', 'on', 'once', 'only', 'or', 'other', 'ought', 'our', 'ours', 'ourselves', 'out', 'over', 'own',
  'same', 'shan\'t', 'she', 'she\'d', 'she\'ll', 'she\'s', 'should', 'shouldn\'t', 'so', 'some', 'such',
  'than', 'that', 'that\'s', 'the', 'their', 'theirs', 'them', 'themselves', 'then', 'there', 'there\'s', 'these',
  'they', 'they\'d', 'they\'ll', 'they\'re', 'they\'ve', 'this', 'those', 'through', 'to', 'too',
  'under', 'until', 'up',
  'very',
  'was', 'wasn\'t', 'we', 'we\'d', 'we\'ll', 'we\'re', 'we\'ve', 'were', 'weren\'t', 'what', 'what\'s', 'when',
  'when\'s', 'where', 'where\'s', 'which', 'while', 'who', 'who\'s', 'whom', 'why', 'why\'s', 'with', 'won\'t', 'would', 'wouldn\'t',
  'you', 'you\'d', 'you\'ll', 'you\'re', 'you\'ve', 'your', 'yours', 'yourself', 'yourselves',
  'please', 'issue', 'problem', 'near', 'facing', 'area', 'daily', 'causing', 'urgent', 'bad', 'road'
]);

// Weighted keywords for Algorithm 1
const CATEGORY_RULES = {
  'Roads & Traffic': {
    department: 'Roads & Traffic',
    deptCode: 'ROADS',
    keywords: {
      'pothole': 4,
      'potholes': 4,
      'crater': 4,
      'asphalt': 3,
      'tar': 3,
      'speedbreaker': 3,
      'divider': 3,
      'traffic': 2,
      'signal': 3,
      'resurfacing': 3,
      'manhole': 2,
      'road': 2,
      'bump': 2,
      'caved': 3,
      'crossing': 2,
      'pavement': 2,
      'congested': 2,
      'paving': 2,
    },
  },
  'Cleanliness & Waste Management': {
    department: 'Cleanliness & Waste Management',
    deptCode: 'SANITATION',
    keywords: {
      'garbage': 4,
      'trash': 4,
      'waste': 4,
      'dump': 4,
      'dumpster': 4,
      'dustbin': 4,
      'litter': 3,
      'debris': 3,
      'filth': 3,
      'stink': 3,
      'smell': 2,
      'rotting': 3,
      'sweeping': 3,
      'overflowing': 3,
      'rubbish': 3,
      'unhygienic': 3,
      'mosquitoes': 2,
    },
  },
  'Water Supply & Drainage': {
    department: 'Water Supply & Drainage',
    deptCode: 'WATER',
    keywords: {
      'leak': 4,
      'leakage': 4,
      'leaking': 4,
      'pipe': 4,
      'burst': 4,
      'pipeline': 4,
      'sewage': 4,
      'drain': 3,
      'drainage': 4,
      'flooding': 3,
      'waterlogging': 4,
      'contamination': 4,
      'contaminated': 4,
      'gutter': 3,
      'sewer': 4,
      'stagnant': 3,
      'low pressure': 3,
      'tap': 2,
    },
  },
  'Street & Public Lighting': {
    department: 'Street & Public Lighting',
    deptCode: 'LIGHTING',
    keywords: {
      'streetlight': 5,
      'streetlights': 5,
      'streetlamp': 4,
      'lamp': 3,
      'bulb': 3,
      'dark': 3,
      'darkness': 3,
      'blackout': 4,
      'flickering': 4,
      'illumination': 3,
      'pole': 2,
      'dangling': 3,
      'wiring': 3,
      'electrocution': 4,
      'night': 2,
    },
  },
  'Public Infrastructure & Facilities': {
    department: 'Public Infrastructure & Facilities',
    deptCode: 'PUBLIC_WORKS',
    keywords: {
      'footpath': 4,
      'sidewalk': 4,
      'bench': 3,
      'benches': 3,
      'shelter': 4,
      'bus stop': 4,
      'toilet': 4,
      'toilets': 4,
      'restroom': 4,
      'bridge': 4,
      'railing': 3,
      'park': 3,
      'playground': 3,
      'tree': 2,
      'branch': 2,
      'fence': 3,
    },
  },
};

/**
 * Tokenize and normalize input string.
 * @param {string} text
 * @returns {Array<string>} Clean token list without stop words
 */
function tokenize(text) {
  if (!text || typeof text !== 'string') return [];
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(token => token.length > 2 && !STOP_WORDS.has(token));
}

/**
 * Algorithm 1: Rule-Based Complaint Classification
 * Predicts the municipal category and department based on weighted keyword matching.
 *
 * @param {string} description
 * @returns {Object} { category, department, deptCode, confidence, scores }
 */
function classifyComplaint(description) {
  const tokens = tokenize(description);
  const scores = {};
  let maxScore = 0;
  let bestCategory = 'Roads & Traffic'; // Default fallback
  let totalScore = 0;

  for (const [category, rule] of Object.entries(CATEGORY_RULES)) {
    let catScore = 0;
    const textLower = (description || '').toLowerCase();

    // Check multi-word keyphrases first
    for (const [kw, weight] of Object.entries(rule.keywords)) {
      if (kw.includes(' ') && textLower.includes(kw)) {
        catScore += weight * 2;
      }
    }

    // Check individual token matches
    for (const token of tokens) {
      if (rule.keywords[token]) {
        catScore += rule.keywords[token];
      }
    }

    scores[category] = catScore;
    totalScore += catScore;
    if (catScore > maxScore) {
      maxScore = catScore;
      bestCategory = category;
    }
  }

  const confidence = totalScore > 0 ? Math.min(1.0, parseFloat((maxScore / (totalScore * 0.75)).toFixed(2))) : 0.0;
  const bestRule = CATEGORY_RULES[bestCategory];

  return {
    category: bestCategory,
    department: bestRule.department,
    deptCode: bestRule.deptCode,
    confidence: Math.max(0.1, confidence),
    isConfident: maxScore >= 4,
    scores,
  };
}

/**
 * Algorithm 2: TF-IDF Text Feature Extraction
 * Computes TF-IDF vector for a query text given a background corpus.
 *
 * @param {string} queryText
 * @param {Array<string>} corpusArray - Array of text descriptions
 * @returns {Map<string, number>} Normalized TF-IDF vector
 */
function computeTfIdf(queryText, corpusArray = []) {
  const queryTokens = tokenize(queryText);
  if (queryTokens.length === 0) return new Map();

  // 1. Term Frequency (TF)
  const termCounts = {};
  for (const t of queryTokens) {
    termCounts[t] = (termCounts[t] || 0) + 1;
  }
  const totalTokens = queryTokens.length;

  // 2. Document Frequency (DF) across corpus
  const allDocs = [...corpusArray, queryText].map(tokenize);
  const N = allDocs.length;
  const df = {};

  for (const doc of allDocs) {
    const uniqueTokens = new Set(doc);
    for (const t of uniqueTokens) {
      df[t] = (df[t] || 0) + 1;
    }
  }

  // 3. Compute TF-IDF weights
  const vector = new Map();
  let normSq = 0;

  for (const [t, count] of Object.entries(termCounts)) {
    const tf = count / totalTokens;
    const docFreq = df[t] || 1;
    const idf = Math.log((1 + N) / (1 + docFreq)) + 1.0;
    const weight = tf * idf;
    vector.set(t, weight);
    normSq += weight * weight;
  }

  // L2-Normalize
  const norm = Math.sqrt(normSq);
  if (norm > 0) {
    for (const [t, w] of vector.entries()) {
      vector.set(t, w / norm);
    }
  }

  return vector;
}

/**
 * Algorithm 4: Cosine Similarity
 * Calculates cosine similarity between two normalized TF-IDF vectors.
 *
 * @param {Map<string, number>} vec1
 * @param {Map<string, number>} vec2
 * @returns {number} Value in [0.0, 1.0]
 */
function cosineSimilarity(vec1, vec2) {
  if (!vec1 || !vec2 || vec1.size === 0 || vec2.size === 0) return 0.0;

  let dotProduct = 0;
  for (const [term, val1] of vec1.entries()) {
    if (vec2.has(term)) {
      dotProduct += val1 * vec2.get(term);
    }
  }

  return Math.min(1.0, Math.max(0.0, parseFloat(dotProduct.toFixed(4))));
}

/**
 * Compare query text against multiple candidate complaints
 * @param {string} queryText
 * @param {Array<{ id: number, description: string }>} candidates
 * @param {number} [threshold=0.5]
 * @returns {Array<Object>} Sorted list of matching duplicates
 */
function findTextDuplicates(queryText, candidates = [], threshold = 0.5) {
  if (!candidates || candidates.length === 0) return [];

  const corpus = candidates.map(c => c.description || '');
  const queryVector = computeTfIdf(queryText, corpus);

  const matches = [];
  for (const c of candidates) {
    const candVector = computeTfIdf(c.description || '', corpus);
    const score = cosineSimilarity(queryVector, candVector);
    if (score >= threshold) {
      matches.push({
        ...c,
        cosineSimilarity: score,
        similarityPercentage: Math.round(score * 100),
      });
    }
  }

  matches.sort((a, b) => b.cosineSimilarity - a.cosineSimilarity);
  return matches;
}

module.exports = {
  tokenize,
  classifyComplaint,
  computeTfIdf,
  cosineSimilarity,
  findTextDuplicates,
};
