import { Application, Router } from 'https://deno.land/x/oak/mod.ts'

const env = Deno.env.toObject()
const HOST = env.HOST || '0.0.0.0'
const PORT = env.PORT || 3000

interface IBook {
  id: string;
  author: string;
  title: string;
}

let books: Array<IBook> = [{
  id: "1",
  author: "Robin Wieruch",
  title: "The Road to React",
}, {
  id: "2",
  author: "Kyle Simpson",
  title: "You Don't Know JS: Scope & Closures",
}, {
  id: "3",
  author: "Andreas A. Antonopoulos",
  title: "Mastering Bitcoin",
}]

const searchBookById = (id: string): (IBook | undefined) => books.filter(book => book.id === id)[0]

const getBook = ({ params, response }: { params: { id: string }; response: any }) => {
  console.log(params)
  const book: IBook | undefined = searchBookById(params.id)
  if (book) {
    response.status = 200
    response.body = book
  } else {
    response.status = 404
    response.body = { message: `Book not found.` }
  }
}

const router = new Router()
router.get('/books/:id', getBook)
// .get('/books', getBooks)
// .post('/books', addBook)
// .put('/books/:id', updateBook)
// .delete('/books/:id', deleteBook)

const app = new Application()

app.use(router.routes())
app.use(router.allowedMethods())


console.log(`Listening on port ${HOST}:${PORT} ...`)
await app.listen(`${HOST}:${PORT}`)
