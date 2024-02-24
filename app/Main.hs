module Main (main) where

main :: IO ()
main = print "holi"
{-
import           System.Console.Haskeline
import qualified Control.Monad.Catch           as MC
import           System.IO
import           System.Environment
import           Control.Exception              ( catch
                                                , IOException
                                                )

import           Control.Monad.Except

import           Data.List
import           Data.Char
import           Text.PrettyPrint.ANSI.Leijen   ( renderPretty
                                                , displayS
                                                )
import           Text.ParserCombinators.Parsec  ( many
                                                , Parser
                                                , parse
                                                )

import           Common
import           PrettyPrinter
import           Untyped
import           Parser

---------------------
--- Interpreter
---------------------

main :: IO ()
main = runInputT defaultSettings main'

main' :: InputT IO ()
main' = do
  args <- lift getArgs
  readevalprint args (S True "" [])

ioExceptionCatcher :: IOException -> IO (Maybe a)
ioExceptionCatcher _ = return Nothing

iname, iprompt :: String
iname = "cálculo lambda no tipado"
iprompt = "UT> "


data State = S
  { inter :: Bool
  ,       -- True, si estamos en modo interactivo.
    lfile :: String
  ,     -- Ultimo archivo cargado (para hacer "reload")
    ve    :: NameEnv Value  -- Entorno con variables globales y su valor
  }

--  read-eval-print loop
readevalprint :: [String] -> State -> InputT IO ()
readevalprint args state@(S inter lfile ve) =
  let rec st = do
        mx <- MC.catch
          (if inter then getInputLine iprompt else lift $ fmap Just getLine)
          (lift . ioExceptionCatcher)
        case mx of
          Nothing -> return ()
          Just "" -> rec st
          Just x  -> do
            c   <- interpretCommand x
            st' <- handleCommand st c
            maybe (return ()) rec st'
  in  do
        state' <- compileFiles (prelude : args) state
        when inter $ lift $ putStrLn
          (  "Intérprete de "
          ++ iname
          ++ ".\n"
          ++ "Escriba :? para recibir ayuda."
          )
        --  enter loop
        rec state' { inter = True }

data Command = Compile CompileForm
             | Print String
             | Recompile
             | Browse
             | Quit
             | Help
             | Noop

data CompileForm = CompileInteractive  String
                 | CompileFile         String

interpretCommand :: String -> InputT IO Command
interpretCommand x = lift $ if ":" `isPrefixOf` x
  then do
    let (cmd, t') = break isSpace x
        t         = dropWhile isSpace t'
    --  find matching commands
    let matching = filter (\(Cmd cs _ _ _) -> any (isPrefixOf cmd) cs) commands
    case matching of
      [] -> do
        putStrLn
          ("Comando desconocido `" ++ cmd ++ "'. Escriba :? para recibir ayuda."
          )
        return Noop
      [Cmd _ _ f _] -> do
        return (f t)
      _ -> do
        putStrLn
          (  "Comando ambigüo, podría ser "
          ++ intercalate ", " [ head cs | Cmd cs _ _ _ <- matching ]
          ++ "."
          )
        return Noop
  else return (Compile (CompileInteractive x))

handleCommand :: State -> Command -> InputT IO (Maybe State)
handleCommand state@(S inter lfile ve) cmd = case cmd of
  Quit   -> lift $ unless inter (putStrLn "!@#$^&*") >> return Nothing
  Noop   -> return (Just state)
  Help   -> lift $ putStr (helpTxt commands) >> return (Just state)
  Browse -> lift $ do
    putStr (unlines $ reverse (nub (map ((\(Global s) -> s) . fst) ve)))
    return (Just state)
  Compile c -> do
    state' <- case c of
      CompileInteractive s -> compilePhrase state s
      CompileFile        f -> compileFile (state { lfile = f }) f
    return (Just state')
  Print s   -> printPhrase s >> return (Just state)
  Recompile -> if null lfile
    then lift $ putStrLn "No hay un archivo cargado.\n" >> return (Just state)
    else handleCommand state (Compile (CompileFile lfile))

data InteractiveCommand = Cmd [String] String (String -> Command) String

commands :: [InteractiveCommand]
commands =
  [ Cmd [":browse"] "" (const Browse) "Ver los nombres en scope"
  , Cmd [":load"]
        "<file>"
        (Compile . CompileFile)
        "Cargar un programa desde un archivo"
  , Cmd [":print"] "<exp>" Print "Imprime un término y sus ASTs sin evaluarlo"
  , Cmd [":reload"]
        "<file>"
        (const Recompile)
        "Volver a cargar el último archivo"
  , Cmd [":quit"]       "" (const Quit) "Salir del intérprete"
  , Cmd [":help", ":?"] "" (const Help) "Mostrar esta lista de comandos"
  ]

helpTxt :: [InteractiveCommand] -> String
helpTxt cs =
  "Lista de comandos:  Cualquier comando puede ser abreviado a :c donde\n"
    ++ "c es el primer caracter del nombre completo.\n\n"
    ++ "<expr>                  evaluar la expresión\n"
    ++ "def <var> = <expr>      definir una variable\n"
    ++ unlines
         (map
           (\(Cmd c a _ d) ->
             let ct = intercalate
                   ", "
                   (map (++ if null a then "" else " " ++ a) c)
             in  ct ++ replicate ((24 - length ct) `max` 2) ' ' ++ d
           )
           cs
         )

compileFiles :: [String] -> State -> InputT IO State
compileFiles xs s =
  foldM (\s x -> compileFile (s { lfile = x, inter = False }) x) s xs

compileFile :: State -> String -> InputT IO State
compileFile state@(S inter lfile v) f = do
  lift $ putStrLn ("Abriendo " ++ f ++ "...")
  let f' = reverse (dropWhile isSpace (reverse f))
  x <- lift $ Control.Exception.catch
    (readFile f')
    (\e -> do
      let err = show (e :: IOException)
      hPutStr stderr
              ("No se pudo abrir el archivo " ++ f' ++ ": " ++ err ++ "\n")
      return ""
    )
  stmts <- parseIO f' (many parseTermStmt) x
  maybe (return state) (foldM handleStmt state) stmts


compilePhrase :: State -> String -> InputT IO State
compilePhrase state x = do
  x' <- parseIO "<interactive>" parseTermStmt x
  maybe (return state) (handleStmt state) x'

printPhrase :: String -> InputT IO ()
printPhrase x = do
  x' <- parseIO "<interactive>" (parseStmt p) x
  maybe (return ()) printStmt x'
 where
  p :: Parser (LamTerm, Term)
  p = do
    a <- parseLamTerm
    return (a, conversion a)

printStmt :: Stmt (LamTerm, Term) -> InputT IO ()
printStmt stmt = lift $ do
  let outtext = case stmt of
        Def x (_, e) -> "def " ++ x ++ " = " ++ render (printTerm e)
        Eval (d, e) ->
          "LamTerm AST:\n"
            ++ show d
            ++ "\n\nTerm AST:\n"
            ++ show e
            ++ "\n\nSe muestra como:\n"
            ++ render (printTermUN e)
            ++ "\n\nSe muestra con nombres arbitrarios como:\n"
            ++ render (printTerm e)
  putStrLn outtext

parseIO :: String -> Parser a -> String -> InputT IO (Maybe a)
parseIO f p x = lift $ case parse (totParser p) f x of
  Left  e -> print e >> return Nothing
  Right r -> return (Just r)

handleStmt :: State -> Stmt Term -> InputT IO State
handleStmt state stmt = lift $ do
  case stmt of
    Def x e -> checkEval x e
    Eval e  -> checkEval it e
 where
  checkEval :: String -> Term -> IO State
  checkEval i t = do
    let v = eval (ve state) t
    when (inter state) $ do
      let outtext = if i == it then render (printTermUN $ quote v) else i
      putStrLn outtext
    return (state { ve = (Global i, v) : ve state })

prelude :: String
prelude = "Ejemplos/Prelude.lam"

it :: String
it = "it"


module Main where

import           Control.Exception              ( catch
                                                , IOException
                                                )
import           Control.Monad.Except
import           Data.Char
import           Data.List
import           Data.Maybe
import           Prelude                 hiding ( print )
import           System.Console.Haskeline
import qualified Control.Monad.Catch           as MC
import           System.Environment
import           System.IO               hiding ( print )
import           Text.PrettyPrint.HughesPJ      ( render
                                                , text
                                                )

import           Common
import           PrettyPrinter
import           Simplytyped
import           Parse
---------------------
--- Interpreter
---------------------

main :: IO ()
main = runInputT defaultSettings main'

main' :: InputT IO ()
main' = do
  args <- lift getArgs
  readevalprint args (S True "" [])

iname, iprompt :: String
iname = "cálculo lambda simplemente tipado"
iprompt = "ST> "

ioExceptionCatcher :: IOException -> IO (Maybe a)
ioExceptionCatcher _ = return Nothing

data State = S
  { inter :: Bool
  ,       -- True, si estamos en modo interactivo.
    lfile :: String
  ,     -- Ultimo archivo cargado (para hacer "reload")
    ve    :: NameEnv Value Type  -- Entorno con variables globales y su valor  [(Name, (Value, Type))]
  }

--  read-eval-print loop
readevalprint :: [String] -> State -> InputT IO ()
readevalprint args state@(S inter lfile ve) =
  let rec st = do
        mx <- MC.catch
          (if inter then getInputLine iprompt else lift $ fmap Just getLine)
          (lift . ioExceptionCatcher)
        case mx of
          Nothing -> return ()
          Just "" -> rec st
          Just x  -> do
            c   <- interpretCommand x
            st' <- handleCommand st c
            maybe (return ()) rec st'
  in  do
        state' <- compileFiles (prelude : args) state
        when inter $ lift $ putStrLn
          (  "Intérprete de "
          ++ iname
          ++ ".\n"
          ++ "Escriba :? para recibir ayuda."
          )
        --  enter loop
        rec state' { inter = True }

data Command = Compile CompileForm
              | Print String
              | Recompile
              | Browse
              | Quit
              | Help
              | Noop
              | FindType String

data CompileForm = CompileInteractive  String
                  | CompileFile         String

interpretCommand :: String -> InputT IO Command
interpretCommand x = lift $ if isPrefixOf ":" x
  then do
    let (cmd, t') = break isSpace x
    let t         = dropWhile isSpace t'
    --  find matching commands
    let matching = filter (\(Cmd cs _ _ _) -> any (isPrefixOf cmd) cs) commands
    case matching of
      [] -> do
        putStrLn
          ("Comando desconocido `" ++ cmd ++ "'. Escriba :? para recibir ayuda."
          )
        return Noop
      [Cmd _ _ f _] -> do
        return (f t)
      _ -> do
        putStrLn
          (  "Comando ambigüo, podría ser "
          ++ concat (intersperse ", " [ head cs | Cmd cs _ _ _ <- matching ])
          ++ "."
          )
        return Noop
  else return (Compile (CompileInteractive x))

handleCommand :: State -> Command -> InputT IO (Maybe State)
handleCommand state@(S inter lfile ve) cmd = case cmd of
  Quit   -> lift $ when (not inter) (putStrLn "!@#$^&*") >> return Nothing
  Noop   -> return (Just state)
  Help   -> lift $ putStr (helpTxt commands) >> return (Just state)
  Browse -> lift $ do
    putStr (unlines [ s | Global s <- reverse (nub (map fst ve)) ])
    return (Just state)
  Compile c -> do
    state' <- case c of
      CompileInteractive s -> compilePhrase state s
      CompileFile        f -> compileFile (state { lfile = f }) f
    return (Just state')
  Print s ->
    let s' = reverse (dropWhile isSpace (reverse (dropWhile isSpace s)))
    in  printPhrase s' >> return (Just state)
  Recompile -> if null lfile
    then lift $ putStrLn "No hay un archivo cargado.\n" >> return (Just state)
    else handleCommand state (Compile (CompileFile lfile))
  FindType s -> do
    x' <- parseIO "<interactive>" term_parse s
    t  <- case x' of
      Nothing -> return $ Left "Error en el parsing."
      Just x  -> return $ infer ve $ conversion $ x
    case t of
      Left  err -> lift (putStrLn ("Error de tipos: " ++ err)) >> return ()
      Right t'  -> lift $ putStrLn $ render $ printType t'
    return (Just state)

data InteractiveCommand = Cmd [String] String (String -> Command) String

commands :: [InteractiveCommand]
commands =
  [ Cmd [":browse"] "" (const Browse) "Ver los nombres en scope"
  , Cmd [":load"]
        "<file>"
        (Compile . CompileFile)
        "Cargar un programa desde un archivo"
  , Cmd [":print"] "<exp>" Print "Imprime un término y sus ASTs"
  , Cmd [":reload"]
        "<file>"
        (const Recompile)
        "Volver a cargar el último archivo"
  , Cmd [":quit"]       ""       (const Quit) "Salir del intérprete"
  , Cmd [":help", ":?"] ""       (const Help) "Mostrar esta lista de comandos"
  , Cmd [":type"]       "<term>" (FindType)   "Inferir el tipo de un término"
  ]

helpTxt :: [InteractiveCommand] -> String
helpTxt cs =
  "Lista de comandos:  Cualquier comando puede ser abreviado a :c donde\n"
    ++ "c es el primer caracter del nombre completo.\n\n"
    ++ "<expr>                  evaluar la expresión\n"
    ++ "def <var> = <expr>      definir una variable\n"
    ++ unlines
         (map
           (\(Cmd c a _ d) ->
             let
               ct =
                 concat
                   (intersperse ", "
                                (map (++ if null a then "" else " " ++ a) c)
                   )
             in  ct ++ replicate ((24 - length ct) `max` 2) ' ' ++ d
           )
           cs
         )

compileFiles :: [String] -> State -> InputT IO State
compileFiles xs s =
  foldM (\s x -> compileFile (s { lfile = x, inter = False }) x) s xs

compileFile :: State -> String -> InputT IO State
compileFile state@(S inter lfile v) f = do
  lift $ putStrLn ("Abriendo " ++ f ++ "...")
  let f' = reverse (dropWhile isSpace (reverse f))
  x <- lift $ Control.Exception.catch
    (readFile f')
    (\e -> do
      let err = show (e :: IOException)
      hPutStr stderr
              ("No se pudo abrir el archivo " ++ f' ++ ": " ++ err ++ "\n")
      return ""
    )
  stmts <- parseIO f' (stmts_parse) x
  maybe (return state) (foldM handleStmt state) stmts


compilePhrase :: State -> String -> InputT IO State
compilePhrase state x = do
  x' <- parseIO "<interactive>" stmt_parse x
  maybe (return state) (handleStmt state) x'

printPhrase :: String -> InputT IO ()
printPhrase x = do
  x' <- parseIO "<interactive>" stmt_parse x
  maybe (return ()) (printStmt . fmap (\y -> (y, conversion y))) x'

printStmt :: Stmt (LamTerm, Term) -> InputT IO ()
printStmt stmt = lift $ do
  let outtext = case stmt of
        Def x (_, e) -> "def " ++ x ++ " = " ++ render (printTerm e)
        Eval (d, e) ->
          "LamTerm AST:\n"
            ++ show d
            ++ "\n\nTerm AST:\n"
            ++ show e
            ++ "\n\nSe muestra como:\n"
            ++ render (printTerm e)
  putStrLn outtext

parseIO :: String -> (String -> ParseResult a) -> String -> InputT IO (Maybe a)
parseIO f p x = lift $ case p x of
  Failed e -> do
    putStrLn (f ++ ": " ++ e)
    return Nothing
  Ok r -> return (Just r)

handleStmt :: State -> Stmt LamTerm -> InputT IO State
handleStmt state stmt = lift $ do
  case stmt of
    Def x e -> checkType x (conversion e)
    Eval e  -> checkType it (conversion e)
 where
  checkType i t = do
    case infer (ve state) t of
      Left  err -> putStrLn ("Error de tipos: " ++ err) >> return state
      Right ty  -> checkEval i t ty
  checkEval i t ty = do
    let v = eval (ve state) t
    _ <- when (inter state) $ do
      let outtext =
            if i == it then render (printTerm (quote v)) else render (text i)
      putStrLn outtext
    return (state { ve = (Global i, (v, ty)) : ve state })

prelude :: String
prelude = "Ejemplos/Prelude.lam"

it :: String
it = "it"
-}