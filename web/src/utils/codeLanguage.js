const FILE_NAME_LANGUAGES = new Map([
  ['dockerfile', 'dockerfile'],
  ['containerfile', 'dockerfile'],
  ['gemfile', 'ruby'],
  ['rakefile', 'ruby'],
  ['vagrantfile', 'ruby'],
  ['.bashrc', 'shell'],
  ['.bash_profile', 'shell'],
  ['.zshrc', 'shell'],
  ['.profile', 'shell'],
])

const EXTENSION_LANGUAGES = new Map([
  ['js', 'javascript'], ['jsx', 'javascript'], ['mjs', 'javascript'], ['cjs', 'javascript'],
  ['ts', 'typescript'], ['tsx', 'typescript'], ['mts', 'typescript'], ['cts', 'typescript'],
  ['py', 'python'], ['pyw', 'python'],
  ['html', 'html'], ['htm', 'html'], ['vue', 'html'], ['hbs', 'handlebars'],
  ['css', 'css'], ['scss', 'scss'], ['sass', 'scss'], ['less', 'less'],
  ['json', 'json'], ['jsonc', 'json'], ['geojson', 'json'],
  ['md', 'markdown'], ['markdown', 'markdown'],
  ['xml', 'xml'], ['svg', 'xml'], ['xsl', 'xml'], ['xslt', 'xml'],
  ['yaml', 'yaml'], ['yml', 'yaml'],
  ['sh', 'shell'], ['bash', 'shell'], ['zsh', 'shell'], ['ksh', 'shell'],
  ['ps1', 'powershell'], ['bat', 'bat'], ['cmd', 'bat'],
  ['go', 'go'], ['java', 'java'], ['kt', 'kotlin'], ['kts', 'kotlin'],
  ['c', 'c'], ['h', 'c'], ['cpp', 'cpp'], ['cc', 'cpp'], ['cxx', 'cpp'],
  ['hpp', 'cpp'], ['hh', 'cpp'], ['hxx', 'cpp'], ['m', 'objective-c'],
  ['rs', 'rust'], ['swift', 'swift'], ['dart', 'dart'],
  ['php', 'php'], ['rb', 'ruby'], ['lua', 'lua'], ['pl', 'perl'], ['pm', 'perl'],
  ['r', 'r'], ['sql', 'sql'], ['graphql', 'graphql'], ['gql', 'graphql'],
  ['ini', 'ini'], ['cfg', 'ini'], ['conf', 'ini'], ['properties', 'ini'], ['toml', 'ini'],
  ['dockerfile', 'dockerfile'], ['proto', 'protobuf'], ['coffee', 'coffeescript'], ['pug', 'pug'],
])

const languageFromShebang = (firstLine) => {
  if (!firstLine.startsWith('#!')) return ''
  if (/\b(?:python|python\d+(?:\.\d+)?)\b/i.test(firstLine)) return 'python'
  if (/\b(?:node|deno|bun)\b/i.test(firstLine)) return 'javascript'
  if (/\b(?:bash|zsh|ksh|dash|ash|sh)\b/i.test(firstLine)) return 'shell'
  if (/\b(?:pwsh|powershell)\b/i.test(firstLine)) return 'powershell'
  if (/\bruby\b/i.test(firstLine)) return 'ruby'
  if (/\bperl\b/i.test(firstLine)) return 'perl'
  if (/\bphp\b/i.test(firstLine)) return 'php'
  return ''
}

const detectLanguageFromContent = (content) => {
  const sample = String(content || '').slice(0, 65536)
  const trimmed = sample.trimStart()
  if (!trimmed) return 'plaintext'

  const shebangLanguage = languageFromShebang(trimmed.split(/\r?\n/, 1)[0])
  if (shebangLanguage) return shebangLanguage
  if (/^<\?php\b/i.test(trimmed)) return 'php'
  if (/^<!doctype\s+html\b/i.test(trimmed) || /<(?:html|head|body|template)\b/i.test(trimmed)) return 'html'
  if (/^<\?xml\b/i.test(trimmed)) return 'xml'

  if (trimmed[0] === '{' || trimmed[0] === '[') {
    try {
      JSON.parse(trimmed)
      return 'json'
    } catch {
      // Continue with code heuristics for object literals and incomplete files.
    }
  }

  if (/^(?:FROM|ARG)\s+\S+/im.test(sample) && /^(?:RUN|COPY|ADD|CMD|ENTRYPOINT)\b/im.test(sample)) return 'dockerfile'
  if (/^package\s+\w+/m.test(sample) && /\bfunc\s+(?:\([^)]*\)\s*)?\w+\s*\(/.test(sample)) return 'go'
  if (/\bfn\s+\w+\s*\([^)]*\)/.test(sample) && /(?:\blet\s+mut\b|\buse\s+[\w:]+|->\s*\w+)/.test(sample)) return 'rust'
  if (/\b(?:public\s+)?(?:class|interface|enum)\s+\w+/.test(sample) && /\b(?:public|private|protected|static)\b/.test(sample)) return 'java'
  if (/^\s*#\s*include\s*[<"]/m.test(sample)) return /\b(?:std::|namespace\s+\w+|class\s+\w+)/.test(sample) ? 'cpp' : 'c'
  if (/^(?:from\s+\S+\s+import\s+|import\s+\S+|def\s+\w+\s*\(|class\s+\w+.*:)/m.test(sample)) return 'python'
  if (/\b(?:SELECT|INSERT\s+INTO|UPDATE\s+\w+\s+SET|CREATE\s+TABLE|ALTER\s+TABLE)\b/i.test(sample)) return 'sql'
  if (/^(?:import|export)\s.+\bfrom\s+['"]|\b(?:const|let|var)\s+\w+\s*=|\bfunction\s+\w+\s*\(/m.test(sample)) return 'javascript'
  if (/^[ \t]*[\w.-]+\s*:\s*[^\n{}]+$/m.test(sample) && (/^---\s*$/m.test(sample) || sample.match(/^[ \t]*[\w.-]+\s*:/gm)?.length >= 2)) return 'yaml'
  if (/^\s*\[[^\]\n]+\]\s*$/m.test(sample) && /^\s*[\w.-]+\s*=.+$/m.test(sample)) return 'ini'
  if (/^(?:set\s+-[a-z]+|(?:if|for|while)\s+.+;?\s+then|[A-Z_][A-Z0-9_]*=\S+)/m.test(sample)) return 'shell'
  return 'plaintext'
}

export const detectCodeLanguage = (fileName, content = '') => {
  const baseName = String(fileName || '').split(/[\\/]/).pop().toLowerCase()
  const exactLanguage = FILE_NAME_LANGUAGES.get(baseName)
  if (exactLanguage) return exactLanguage

  const dot = baseName.lastIndexOf('.')
  const extension = dot >= 0 ? baseName.slice(dot + 1) : ''
  const extensionLanguage = EXTENSION_LANGUAGES.get(extension)
  if (extensionLanguage) return extensionLanguage

  return detectLanguageFromContent(content)
}
